-- RANDOM HUB | ANIME PIECE V1.3 | SCRIPT SEPARADO | SEM KEY
-- RANDOM HUB V1.3
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local function getServiceSafe(name)
    local ok, service = pcall(function() return game:GetService(name) end)
    if ok then return service end
    return nil
end
local VirtualInputManager = getServiceSafe("VirtualInputManager")
local VirtualUser = getServiceSafe("VirtualUser")
local GuiService = getServiceSafe("GuiService")
local StarterGui = getServiceSafe("StarterGui")
local CoreGui = getServiceSafe("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

pcall(function()
    if type(_G.__RamdomHubStop) == "function" then _G.__RamdomHubStop() end
end)

local UIParent = nil
pcall(function()
    if type(gethui) == "function" then
        local candidate = gethui()
        if typeof(candidate) == "Instance" then
            UIParent = candidate
        end
    end
end)
if not UIParent then
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            or LocalPlayer:WaitForChild("PlayerGui", 10)
        if playerGui and playerGui:IsA("PlayerGui") then
            UIParent = playerGui
        end
    end)
end
if not UIParent then
    pcall(function()
        if CoreGui and CoreGui:IsA("CoreGui") then UIParent = CoreGui end
    end)
end
if not UIParent or typeof(UIParent) ~= "Instance" then
    warn("[Random Hub | Anime Piece] Falha ao localizar PlayerGui/CoreGui; execução cancelada para evitar erro de interface.")
    return
end

for _, name in ipairs({"FlyUI", "FlyToggle"}) do
    pcall(function()
        local old = UIParent:FindFirstChild(name)
        if old then old:Destroy() end
    end)
    pcall(function()
        local old = LocalPlayer:FindFirstChildOfClass("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end)
end

local CONFIG = {
    Version = "1.3",
    UISize = UDim2.fromOffset(600, 460),
    UIOffset = UDim2.new(0.5, -300, 0.5, -230),
    UIScale = 1,
}

local function getScaledWindowOffset()
    return UDim2.new(0.5, -(CONFIG.UISize.X.Offset * CONFIG.UIScale) / 2, 0.5, -(CONFIG.UISize.Y.Offset * CONFIG.UIScale) / 2)
end

local Theme = {
    Bg          = Color3.fromRGB(50, 50, 56),
    BgSecondary = Color3.fromRGB(61, 61, 68),
    Card        = Color3.fromRGB(70, 70, 77),
    CardHover   = Color3.fromRGB(82, 82, 89),
    Stroke      = Color3.fromRGB(60, 60, 80),
    Accent1     = Color3.fromRGB(0, 0, 0),
    Accent2     = Color3.fromRGB(0, 120, 255),
    Text        = Color3.fromRGB(240, 240, 250),
    TextDim     = Color3.fromRGB(150, 150, 170),
    Danger      = Color3.fromRGB(255, 80, 110),
}

local connections = {}
local activeTweens = {}
local destroyed = false
local uiOpen = true
local stopAutoFarm = nil
local stopCombat = nil
local Stoppers = {}
local autoQuestEnabled = false
local QuestRuntime = {
    Farming = false, SkillBusy = false, Interacting = false,
    WaitForFarmSelection = false, HasFarmSelection = false,
    -- O Auto Quest decide quando tomar o controle do movimento.
    QuestPriority = false, RepeatEnabled = false,
    RepeatCompletionPending = false, RepeatAtQuestNpc = false,
    RepeatArmAt = 0,
}
local farmDistance = 1.0

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function addCorner(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = object
    return corner
end

local function addStroke(object, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.Stroke
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = object
    return stroke
end

local function addGradient(object, color1, color2, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(color1, color2)
    gradient.Rotation = rotation or 0
    gradient.Parent = object
    return gradient
end

local function tween(object, properties, duration, style, direction)
    if destroyed or not object then return nil end
    local info = TweenInfo.new(
        duration or 0.18,
        style or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out
    )
    local animation = TweenService:Create(object, info, properties)
    activeTweens[animation] = true
    animation.Completed:Connect(function()
        activeTweens[animation] = nil
    end)
    animation:Play()
    return animation
end

local TOGGLE_ON = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 120, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
})
local TOGGLE_OFF = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 110)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 70)),
})

local function runSection(name, builder)
    local ok, err = pcall(builder)
    if not ok then
        warn("[Random Hub] Erro na secao '" .. tostring(name) .. "': " .. tostring(err))
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlyUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = UIParent

-- Gradual visual reveal for scripted long-distance teleports (over 500 studs).
-- NOTE: Roblox owns real streaming/render distance. Lighting fog simulates a
-- visual radius while RequestStreamAroundAsync warms up the destination.
-- The FPS Boost map-distance worker also follows this radius while enabled.
local Graphics -- forward declaration for the FPS Boost implementation below
local TeleportLoading = {
    number = 0, current = nil, distanceThreshold = 500,
    initialRadius = 50, radiusStep = 100, stepSeconds = 0.5,
    -- Keep revealing past the old 1550-stud cutoff instead of abruptly
    -- restoring the original fog distance (which made the entire map pop in).
    -- After 1550, increment the horizon progressively faster for far-off scenery.
    smoothGrowthAfter = 1550, farGrowthFraction = 0.35,
}
local teleportLighting = game:GetService("Lighting")

function TeleportLoading.isLong(root, destination)
    return root and root.Parent and typeof(destination) == "Vector3"
        and (root.Position - destination).Magnitude > TeleportLoading.distanceThreshold
end

function TeleportLoading.isActive(ticket)
    local state = TeleportLoading.current
    return not destroyed and state ~= nil and state.ticket == ticket and not state.cancelled
end

function TeleportLoading.finish(ticket)
    local state = TeleportLoading.current
    if not state or (ticket and ticket ~= state.ticket) then return end
    state.cancelled = true
    TeleportLoading.current = nil
    -- Restore lighting and the FPS Boost radius, including after a cancelled TP.
    if state.applied then
        pcall(function()
            teleportLighting.FogStart = state.fogStart
            teleportLighting.FogEnd = state.fogEnd
        end)
        if Graphics and Graphics.enabled then
            Graphics.maxMapDistance = state.fpsRadius or 450
        end
        for atmosphere, previousParent in pairs(state.atmospheres or {}) do
            pcall(function()
                if atmosphere.Parent == nil and previousParent and previousParent.Parent then
                    atmosphere.Parent = previousParent
                end
            end)
        end
    end
end

function TeleportLoading.begin(owner)
    if destroyed then return nil end
    -- Preserve the ORIGINAL visual baseline across back-to-back teleports.
    -- Calling finish() here would flash the entire map for one frame.
    local old = TeleportLoading.current
    if old then old.cancelled = true end
    TeleportLoading.current = nil
    TeleportLoading.number = TeleportLoading.number + 1
    local id = TeleportLoading.number
    TeleportLoading.current = {
        ticket = id, owner = owner, cancelled = false,
        streamReady = true, applied = false,
        fogStart = old and old.fogStart or teleportLighting.FogStart,
        fogEnd = old and old.fogEnd or teleportLighting.FogEnd,
        fpsRadius = old and old.fpsRadius or (Graphics and Graphics.maxMapDistance or nil),
        atmospheres = old and old.atmospheres or {},
    }
    -- Long jumps are scheduled 0.5 s after begin() in every teleport path.
    -- Restrict visibility NOW, while still at the origin, instead of at arrival.
    TeleportLoading.activate(id)
    return id
end

-- Prep requests run separately and never block the main heartbeat / farm loop.
function TeleportLoading.preload(ticket, position)
    if not TeleportLoading.isActive(ticket) then return end
    if not workspace.StreamingEnabled or type(LocalPlayer.RequestStreamAroundAsync) ~= "function" then return end
    -- Only ONE optional preload at the destination. The previous version
    -- requested three nearby locations, which could trigger large streaming
    -- bursts just as the visibility transition was running.
    local state = TeleportLoading.current
    task.spawn(function()
        pcall(function() LocalPlayer:RequestStreamAroundAsync(position, 0.5) end)
        if TeleportLoading.isActive(ticket) then state.streamReady = true end
    end)
end

-- Called immediately BEFORE relocating the character, without a black overlay.
function TeleportLoading.activate(ticket)
    if not TeleportLoading.isActive(ticket) then return end
    local state = TeleportLoading.current
    if state.applied then return end
    state.applied = true
    -- Atmosphere can override Lighting's FogStart/FogEnd. Temporarily detach
    -- active atmosphere objects only (FPS Boost may already have detached them).
    for _, object in ipairs(teleportLighting:GetChildren()) do
        if object:IsA("Atmosphere") then
            state.atmospheres[object] = object.Parent
            pcall(function() object.Parent = nil end)
        end
    end
    pcall(function()
        teleportLighting.FogStart = 38
        teleportLighting.FogEnd = TeleportLoading.initialRadius
    end)
    if Graphics and Graphics.enabled then Graphics.maxMapDistance = 50 end
end

-- After teleporting, reveal in 100-stud steps every 0.5 s near the player.
-- At longer ranges use gradually larger steps, instead of an abrupt jump
-- from the old 1550-stud cap to FogEnd's original (often 100000) value.
function TeleportLoading.fadeOut(ticket)
    if not TeleportLoading.isActive(ticket) then return end
    local state = TeleportLoading.current
    if not state.applied then TeleportLoading.activate(ticket) end
    if not TeleportLoading.isActive(ticket) or state.revealStarted then return end
    state.revealStarted = true
    task.spawn(function()
        local original = tonumber(state.fogEnd) or 100000
        if original ~= original or original == math.huge then original = 100000 end
        local target = math.max(TeleportLoading.initialRadius, original)
        if Graphics and Graphics.enabled then
            target = math.max(TeleportLoading.initialRadius, math.min(target, state.fpsRadius or 450))
        end
        local radius = TeleportLoading.initialRadius
        while TeleportLoading.isActive(ticket) and radius < target do
            task.wait(TeleportLoading.stepSeconds)
            if not TeleportLoading.isActive(ticket) then return end
            local step = TeleportLoading.radiusStep
            if radius >= TeleportLoading.smoothGrowthAfter then
                -- Distant scenery opens faster, still without a one-frame reset.
                step = math.max(step, math.floor(radius * TeleportLoading.farGrowthFraction))
            end
            radius = math.min(target, radius + step)
            pcall(function()
                teleportLighting.FogStart = math.max(0, radius - 40)
                teleportLighting.FogEnd = radius
            end)
            if Graphics and Graphics.enabled then Graphics.maxMapDistance = radius end
        end
        if TeleportLoading.isActive(ticket) then TeleportLoading.finish(ticket) end
    end)
end

function TeleportLoading.waitForReady(ticket, maxWait)
    local started = os.clock()
    while TeleportLoading.isActive(ticket) and not TeleportLoading.current.streamReady
        and os.clock() - started < (maxWait or 0.6) do
        task.wait(0.05)
    end
end

function TeleportLoading.cancelOwner(owner)
    local state = TeleportLoading.current
    if state and state.owner == owner then TeleportLoading.finish(state.ticket) end
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = CONFIG.UISize
Main.Position = CONFIG.UIOffset
Main.BackgroundColor3 = Theme.Bg
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui
addCorner(Main, 18)
addStroke(Main, Theme.Stroke, 1, 0.3)
addGradient(Main, Color3.fromRGB(60, 60, 66), Color3.fromRGB(44, 44, 50), 90)

local MainScale = Instance.new("UIScale")
MainScale.Scale = CONFIG.UIScale
MainScale.Parent = Main

local HEADER_H = 72
local CloseBtn = nil

runSection("Header", function()
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, HEADER_H)
    Header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Header.BorderSizePixel = 0
    Header.ZIndex = 2
    Header.Parent = Main
    addCorner(Header, 18)
    addGradient(Header, Theme.Accent1, Theme.Accent2, 45)

    local HeaderCover = Instance.new("Frame")
    HeaderCover.Name = "HeaderCover"
    HeaderCover.Size = UDim2.new(1, 0, 0, 18)
    HeaderCover.Position = UDim2.new(0, 0, 1, -18)
    HeaderCover.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    HeaderCover.BorderSizePixel = 0
    HeaderCover.ZIndex = 3
    HeaderCover.Parent = Header
    addGradient(HeaderCover, Theme.Accent1, Theme.Accent2, 45)

    local Logo = Instance.new("TextLabel")
    Logo.Name = "Logo"
    Logo.Size = UDim2.fromOffset(42, 42)
    Logo.Position = UDim2.new(0, 20, 0.5, -21)
    Logo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Logo.BackgroundTransparency = 0.85
    Logo.Text = "🎲"
    Logo.TextColor3 = Color3.fromRGB(255, 255, 255)
    Logo.Font = Enum.Font.GothamBold
    Logo.TextSize = 24
    Logo.ZIndex = 4
    Logo.Parent = Header
    addCorner(Logo, 12)

    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -180, 0, 24)
    Title.Position = UDim2.new(0, 74, 0, 16)
    Title.BackgroundTransparency = 1
    Title.Text = "RandomHub | Anime Piece"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 18
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.ZIndex = 4
    Title.Parent = Header

    local Subtitle = Instance.new("TextLabel")
    Subtitle.Name = "Subtitle"
    Subtitle.Size = UDim2.new(1, -180, 0, 16)
    Subtitle.Position = UDim2.new(0, 74, 0, 40)
    Subtitle.BackgroundTransparency = 1
    Subtitle.Text = "v" .. CONFIG.Version
    Subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    Subtitle.TextTransparency = 0.3
    Subtitle.Font = Enum.Font.Gotham
    Subtitle.TextSize = 12
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    Subtitle.ZIndex = 4
    Subtitle.Parent = Header

    CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.fromOffset(32, 32)
    CloseBtn.Position = UDim2.new(1, -44, 0, 20)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.BackgroundTransparency = 0.85
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 16
    CloseBtn.ZIndex = 5
    CloseBtn.AutoButtonColor = false
    CloseBtn.Parent = Header
    addCorner(CloseBtn, 10)
    connect(CloseBtn.MouseEnter, function()
        tween(CloseBtn, {BackgroundTransparency = 0.6, BackgroundColor3 = Theme.Danger}, 0.15)
    end)
    connect(CloseBtn.MouseLeave, function()
        tween(CloseBtn, {BackgroundTransparency = 0.85, BackgroundColor3 = Color3.fromRGB(255, 255, 255)}, 0.15)
    end)

    do
        local dragging = false
        local dragStart = nil
        local startPosition = nil
        connect(Header.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPosition = Main.Position
            end
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        connect(UserInputService.InputChanged, function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                Main.Position = UDim2.new(
                    startPosition.X.Scale, startPosition.X.Offset + delta.X,
                    startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
                )
            end
        end)
    end
end)

local Pages = {}

runSection("Navigation", function()
    local SIDEBAR_W = 150
    local Sidebar = Instance.new("ScrollingFrame")
    Sidebar.CanvasSize = UDim2.fromOffset(0, 0)
    Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Sidebar.ScrollingDirection = Enum.ScrollingDirection.Y
    Sidebar.ScrollBarThickness = 0
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H - 24)
    Sidebar.Position = UDim2.new(0, 16, 0, HEADER_H + 12)
    Sidebar.BackgroundColor3 = Theme.BgSecondary
    Sidebar.BorderSizePixel = 0
    Sidebar.ZIndex = 2
    Sidebar.Parent = Main
    addCorner(Sidebar, 12)
    addStroke(Sidebar, Theme.Stroke, 1, 0.5)

    local SidebarLayout = Instance.new("UIListLayout")
    SidebarLayout.Padding = UDim.new(0, 8)
    SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SidebarLayout.Parent = Sidebar

    local SidebarPad = Instance.new("UIPadding")
    SidebarPad.PaddingTop = UDim.new(0, 10)
    SidebarPad.PaddingLeft = UDim.new(0, 8)
    SidebarPad.PaddingRight = UDim.new(0, 8)
    SidebarPad.Parent = Sidebar

    local ContentHolder = Instance.new("Frame")
    ContentHolder.Name = "ContentHolder"
    ContentHolder.Size = UDim2.new(1, -(SIDEBAR_W + 48), 1, -(HEADER_H + 24))
    ContentHolder.Position = UDim2.new(0, SIDEBAR_W + 32, 0, HEADER_H + 12)
    ContentHolder.BackgroundTransparency = 1
    ContentHolder.ClipsDescendants = true
    ContentHolder.ZIndex = 2
    ContentHolder.Parent = Main

    local function createPage(name, visible, useVerticalLayout)
        local page = Instance.new((name == "Config" or name == "AutoStats" or name == "Fruit" or name == "AutoQuest" or name == "AutoFarm" or name == "AutoItems" or name == "Combat") and "ScrollingFrame" or "Frame")
        page.Name = name
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = visible == true
        page.ZIndex = 2
        if name == "Config" or name == "AutoStats" or name == "Fruit" or name == "AutoQuest" or name == "AutoFarm" or name == "AutoItems" or name == "Combat" then
            page.BorderSizePixel = 0
            page.ScrollBarThickness = 4
            page.ScrollBarImageColor3 = Theme.Accent2
            page.ScrollingDirection = Enum.ScrollingDirection.Y
            page.CanvasSize = UDim2.fromOffset(0, 0)
            page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        end
        if name == "AutoItems" then
            page.ScrollingEnabled = true
            page.Active = true
            page.ClipsDescendants = true
            local padding = Instance.new("UIPadding")
            padding.PaddingBottom = UDim.new(0, 8)
            padding.PaddingRight = UDim.new(0, 6)
            padding.Parent = page
        end
        page.Parent = ContentHolder
        if useVerticalLayout then
            local layout = Instance.new("UIListLayout")
            layout.Padding = UDim.new(0, name == "AutoItems" and 8 or 10)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Parent = page
        end
        Pages[name] = page
        return page
    end

    createPage("Home", true, false)
    createPage("Combat", false, true)
    createPage("AutoFarm", false, true)
    createPage("AutoQuest", false, true)
    createPage("AutoItems", false, true)
    createPage("Fruit", false, true)
    createPage("AutoStats", false, true)
    createPage("Config", false, true)
    createPage("Teleport", false, true)

    local function createNavTab(id, order)
        local button = Instance.new("TextButton")
        button.Name = "Tab_" .. id
        button.Size = UDim2.new(1, 0, 0, 40)
        button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        button.BackgroundTransparency = id == "Home" and 0 or 1
        button.BorderSizePixel = 0
        button.Text = ""
        button.AutoButtonColor = false
        button.LayoutOrder = order
        button.ZIndex = 3
        button.Parent = Sidebar
        addCorner(button, 8)
        addGradient(button, Theme.Accent1, Theme.Accent2, 0)

        local label = Instance.new("TextLabel")
        label.Name = "TabLabel"
        label.Size = UDim2.new(1, -24, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = id == "AutoQuest" and "Auto Quest" or (id == "AutoFarm" and "Auto Farm" or (id == "AutoItems" and "Auto Items" or (id == "AutoStats" and "Auto Stats" or id)))
        label.TextColor3 = id == "Home" and Color3.fromRGB(245, 248, 255) or Color3.fromRGB(190, 201, 224)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 4
        label.Parent = button

        local indicator = Instance.new("Frame")
        indicator.Name = "Indicator"
        indicator.Size = UDim2.new(0, 3, 0.82, 0)
        indicator.Position = UDim2.new(0, 0, 0.5, -16)
        indicator.BackgroundColor3 = Theme.Accent2
        indicator.BorderSizePixel = 0
        indicator.Visible = id == "Home"
        indicator.ZIndex = 5
        indicator.Parent = button
        addCorner(indicator, 2)
        local stroke = addStroke(button, Color3.fromRGB(42, 120, 255), 1, id == "Home" and 0.28 or 1)
        return {button = button, label = label, indicator = indicator, stroke = stroke}
    end

    local Tabs = {
        Home = createNavTab("Home", 1),
        Combat = createNavTab("Combat", 2),
        AutoFarm = createNavTab("AutoFarm", 3),
        AutoQuest = createNavTab("AutoQuest", 4),
        AutoItems = createNavTab("AutoItems", 5),
        Fruit = createNavTab("Fruit", 6),
        AutoStats = createNavTab("AutoStats", 7),
        Teleport = createNavTab("Teleport", 8),
        Config = createNavTab("Config", 9),
    }
    local currentPage = "Home"
    local function setActivePage(name)
        if not Pages[name] then return end
        currentPage = name
        for pageName, page in pairs(Pages) do
            page.Visible = pageName == name
        end
        for tabName, info in pairs(Tabs) do
            local active = tabName == name
            info.button.BackgroundTransparency = active and 0 or 1
            info.indicator.Visible = active
            info.stroke.Transparency = active and 0.28 or 1
            info.label.TextTransparency = active and 0 or 0.08
            info.label.TextColor3 = active and Color3.fromRGB(245, 248, 255) or Color3.fromRGB(190, 201, 224)
        end
    end
    for name, info in pairs(Tabs) do
        local tabName = name
        local tabInfo = info
        connect(tabInfo.button.MouseButton1Click, function() setActivePage(tabName) end)
        connect(tabInfo.button.MouseEnter, function()
            if currentPage ~= tabName then tween(tabInfo.button, {BackgroundTransparency = 0.45}, 0.12) end
        end)
        connect(tabInfo.button.MouseLeave, function()
            if currentPage ~= tabName then tween(tabInfo.button, {BackgroundTransparency = 1}, 0.12) end
        end)
    end
end)

runSection("Home", function()
    local HomePage = Pages.Home
    -- Update notes shown only on the Home tab.
    local UpdateCard = Instance.new("Frame")
    UpdateCard.Name = "UpdateV13Card"
    UpdateCard.Size = UDim2.new(1, 0, 0, 270)
    UpdateCard.Position = UDim2.fromOffset(0, 68)
    UpdateCard.BackgroundColor3 = Theme.BgSecondary
    UpdateCard.BorderSizePixel = 0
    UpdateCard.Parent = HomePage
    addCorner(UpdateCard, 14)
    addStroke(UpdateCard, Theme.Stroke, 1, 0.35)

    local function updateLabel(name, value, y, height, font, size, color)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Position = UDim2.fromOffset(18, y)
        label.Size = UDim2.new(1, -36, 0, height)
        label.BackgroundTransparency = 1
        label.Text = value
        label.Font = font
        label.TextSize = size
        label.TextColor3 = color
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Parent = UpdateCard
        return label
    end

    updateLabel("UpdateTitle", "UPDATE VERSION V1.3", 14, 28, Enum.Font.GothamBold, 19, Theme.Text)
    local Separator = Instance.new("Frame")
    Separator.Name = "UpdateSeparator"
    Separator.Position = UDim2.fromOffset(18, 47)
    Separator.Size = UDim2.new(1, -36, 0, 1)
    Separator.BackgroundColor3 = Theme.Accent2
    Separator.BorderSizePixel = 0
    Separator.Parent = UpdateCard

    updateLabel("UpdateSubtitle", "NEW FEATURES", 57, 22, Enum.Font.GothamBold, 13, Theme.Accent2)
    local features = {
        "Improved Auto Farm",
        "Improved Safe Farm",
        "Add Auto All Sword",
    }
    for index, feature in ipairs(features) do
        updateLabel("Feature" .. index, "+ " .. feature, 85 + (index - 1) * 23, 21, Enum.Font.Gotham, 13, Theme.Text)
    end
    updateLabel("UpdateVersion", "Version: V1.3", 237, 21, Enum.Font.GothamBold, 12, Theme.TextDim)

    local DiscordCard = Instance.new("Frame")
    DiscordCard.Name = "DiscordCard"
    DiscordCard.Size = UDim2.new(1, 0, 0, 56)
    DiscordCard.BackgroundColor3 = Theme.Accent1
    DiscordCard.BorderSizePixel = 0
    DiscordCard.LayoutOrder = 1
    DiscordCard.Parent = HomePage
    addCorner(DiscordCard, 14)
    addStroke(DiscordCard, Theme.Stroke, 1, 0.5)
    addGradient(DiscordCard, Theme.Accent1, Theme.Accent2, 45)

    local DiscordText = Instance.new("TextLabel")
    DiscordText.Name = "DiscordText"
    DiscordText.Size = UDim2.new(1, -32, 1, 0)
    DiscordText.Position = UDim2.new(0, 16, 0, 0)
    DiscordText.BackgroundTransparency = 1
    DiscordText.Text = "Join Discord"
    DiscordText.TextColor3 = Color3.fromRGB(255, 255, 255)
    DiscordText.Font = Enum.Font.GothamBold
    DiscordText.TextSize = 16
    DiscordText.TextXAlignment = Enum.TextXAlignment.Center
    DiscordText.Parent = DiscordCard

    local DiscordBtn = Instance.new("TextButton")
    DiscordBtn.Name = "DiscordButton"
    DiscordBtn.Size = UDim2.new(1, 0, 1, 0)
    DiscordBtn.BackgroundTransparency = 1
    DiscordBtn.Text = ""
    DiscordBtn.ZIndex = 3
    DiscordBtn.Parent = DiscordCard
    connect(DiscordBtn.MouseButton1Click, function()
        local url = "https://discord.gg/wstMsZp2za"
        local opened = pcall(function()
            GuiService:OpenBrowserWindow(url)
        end)
        if not opened then
            local copied = false
            local clip = nil
            pcall(function()
                if type(setclipboard) == "function" then clip = setclipboard end
            end)
            if clip then copied = pcall(clip, url) end
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Discord",
                    Text = copied and "Link copied to clipboard!" or "Open this invite: " .. url,
                    Duration = 4,
                })
            end)
        end
    end)
end)

local function createStyledCard(parent, name, height, order)
    local card = Instance.new("Frame")
    card.Name = name
    card.Size = UDim2.new(1, 0, 0, height)
    card.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    card.BorderSizePixel = 0
    card.LayoutOrder = order
    card.Parent = parent
    addCorner(card, 14)
    addStroke(card, Theme.Stroke, 1, 0.5)
    addGradient(card, Color3.fromRGB(0, 0, 0), Color3.fromRGB(0, 0, 0), 90)
    return card
end

local function createCombatToggle(parent, objectName, titleText, layoutOrder, callback)
    local card = createStyledCard(parent, objectName, 64, layoutOrder)
    local clickArea = Instance.new("TextButton")
    clickArea.Name = "ClickArea"
    clickArea.Size = UDim2.new(1, 0, 1, 0)
    clickArea.BackgroundTransparency = 1
    clickArea.BorderSizePixel = 0
    clickArea.Text = ""
    clickArea.AutoButtonColor = false
    clickArea.ZIndex = 2
    clickArea.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -110, 1, 0)
    title.Position = UDim2.fromOffset(16, 0)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 3
    title.Parent = card

    local track = Instance.new("TextButton")
    track.Name = "Toggle"
    track.Size = UDim2.fromOffset(52, 28)
    track.Position = UDim2.new(1, -68, 0.5, -14)
    track.BackgroundColor3 = Color3.new(1, 1, 1)
    track.BorderSizePixel = 0
    track.Text = ""
    track.AutoButtonColor = false
    track.ZIndex = 4
    track.Parent = card
    addCorner(track, 14)
    local trackStroke = addStroke(track, Theme.Stroke, 1, 0.3)
    local trackGradient = Instance.new("UIGradient")
    trackGradient.Color = TOGGLE_OFF
    trackGradient.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(22, 22)
    knob.Position = UDim2.new(0, 3, 0.5, -11)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    knob.Parent = track
    addCorner(knob, 11)

    local enabled = false
    local function setState(state)
        enabled = state == true
        trackGradient.Color = enabled and TOGGLE_ON or TOGGLE_OFF
        trackStroke.Transparency = enabled and 0.6 or 0.3
        tween(knob, {Position = enabled and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11)}, 0.18)
        if callback then callback(enabled) end
    end
    connect(clickArea.MouseButton1Click, function() setState(not enabled) end)
    connect(track.MouseButton1Click, function() setState(not enabled) end)
    return setState, function() return enabled end, card
end


local combatAutoAttackClickOffscreen = nil

local World = {humanoids = {}, texts = {}, gui = {}, prompts = {}, fruits = {}, chests = {}, stats = {}, islands = {}, islandPositions = setmetatable({}, {__mode = "k"}), islandRevision = 0, revision = 0, ready = false}
local WorldBoss = {
    Enabled = false,
    Selected = nil,
    Target = nil,
    -- Each boss name has its own built-in spawn coordinate; no extra GUI is required.
    -- This position is used for teleporting, searching within 250 studs and returning after a kill.
    Camp = {
        ["Dual Swordsman"] = Vector3.new(3556.62, 36.54, 2724.08),
        ["Cursed Prodigy"] = Vector3.new(4289.49, 9.45, 403.84),
    },
    DropCamps = {
        ["Overtime Sorcerer"] = Vector3.new(5489.89, -205.88, -2002.37),
        ["Crimson King"] = Vector3.new(200.94, 5.54, 3561.48),
    },
    Summoners = {
        ["Dual Swordsman"] = "Seraphina",
        ["Cursed Prodigy"] = "Noko",
    },
    Requirements = {
        ["Dual Swordsman"] = {Item = "Dual Orb", SourceNames = {"Emerald Swordsman"}, Position = Vector3.new(3791.40, 41.83, 2575.56)},
        ["Cursed Prodigy"] = {Item = "Prodigy Orb", SourceNames = {"White Panda", "Panda"}, Position = Vector3.new(4666.56, 16.12, 225.38), BossAliases = {"Itadori"}},
    },
    MaterialTarget = nil,
    Phase = nil,
    Drops = setmetatable({}, {__mode = "k"}),
    DropKeys = {dualorb = true, prodigyorb = true},
    SearchRadius = 250,
    Stop = nil,
}
local Motion = {farmTeleportInterval = 0.01, owner = nil, speed = 125, threshold = 15, manualUntil = 0, blocked = setmetatable({}, {__mode = "k"}), streamToken = 0, streamPending = false, streamReady = false, streamPosition = nil, manualGeneration = 0}
local ManualFlight = {Enabled = false, Speed = 80}
local SafeMode = {Enabled = false}
local Landing = {}
local getMobRoot, getMobHumanoid, isValidFarmMob, collectFarmMobTypes

runSection("Runtime", function()
    local RunService = game:GetService("RunService")
    local zero = Vector3.new(0, 0, 0)
    local validation = setmetatable({}, {__mode = "k"})

    function World.emit(signal, ...)
        World.lastCallbackError = nil
        local args = table.pack(...)
        if type(getconnections) == "function" then
            local ok, listeners = pcall(getconnections, signal)
            if ok and type(listeners) == "table" then
                local enabled = false
                for _, listener in ipairs(listeners) do
                    local readable, value = pcall(function() return listener.Enabled end)
                    if not readable or value ~= false then enabled = true; break end
                end
                if enabled and type(firesignal) == "function" then
                    local sent, err = pcall(firesignal, signal, table.unpack(args, 1, args.n))
                    if not sent then World.lastCallbackError = tostring(err) end
                    return sent
                end
                local sentAny = false
                for _, listener in ipairs(listeners) do
                    local readable, value = pcall(function() return listener.Enabled end)
                    if not readable or value ~= false then
                        local sent, err = pcall(function()
                            if type(listener.Fire) == "function" then listener:Fire(table.unpack(args, 1, args.n))
                            elseif type(listener.Function) == "function" then listener.Function(table.unpack(args, 1, args.n))
                            else error("Callback indisponivel") end
                        end)
                        sentAny = sentAny or sent
                        if not sent then World.lastCallbackError = tostring(err) end
                    end
                end
                return sentAny
            end
        end
        if type(firesignal) == "function" then return pcall(firesignal, signal, table.unpack(args, 1, args.n)) end
        return false
    end

    local function invalidateMobValidation(object)
        if not object or not (object:IsA("ProximityPrompt") or object:IsA("ClickDetector")
            or object:IsA("BillboardGui") or object:IsA("TextLabel")
            or object:IsA("TextButton") or object:IsA("TextBox")) then
            return
        end
        local node = object.Parent
        while node and node ~= workspace do
            if node:IsA("Model") then validation[node] = nil end
            node = node.Parent
        end
    end

    function World.root(object)
        if not object or not object.Parent then return nil end
        if object:IsA("BasePart") then return object end
        return object:FindFirstChild("HumanoidRootPart") or object:FindFirstChild("Handle")
            or (object:IsA("Model") and object.PrimaryPart)
            or object:FindFirstChild("UpperTorso") or object:FindFirstChild("Torso")
            or object:FindFirstChildWhichIsA("BasePart", true)
    end

    getMobRoot = World.root
    getMobHumanoid = function(model)
        return model and model.Parent and model:FindFirstChildOfClass("Humanoid")
    end

    World.fruitCatalog = {"Copy", "Kilo", "Warrior", "Bomb", "Flame", "Emperor", "Scarlet", "Quake", "Beast", "Infinity", "Vessel"}
    local FRUIT_NAMES = {}
    for _, name in ipairs(World.fruitCatalog) do FRUIT_NAMES[string.lower(name)] = name end
    local fruitLabels = setmetatable({}, {__mode = "k"})

    function World.fruitKey(value)
        return (string.lower(tostring(value or "")):gsub("<[^>]*>", ""):gsub("[^%w]", ""):gsub("%d+$", ""))
    end

    function World.fruitAlias(value)
        local key = World.fruitKey(value):gsub("fruit$", "")
        return FRUIT_NAMES[key]
    end

    function World.fruitName(value)
        return World.fruitAlias(value) ~= nil
    end

    function World.fruitAncestor(object)
        local node = object and object.Parent
        while node and node ~= workspace do
            if (node:IsA("Model") or node:IsA("Tool") or node:IsA("BasePart")) and World.fruitName(node.Name) then return node end
            node = node.Parent
        end
    end

    -- Os frutos no chao exibem "Bomb Fruit" em ObjectText e "[Take]" em ActionText.
    -- Assim nao dependemos do nome interno do modelo (que pode ser Part/DevilFruit).
    function World.isTakePrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") then return false end
        local action = World.fruitKey(prompt.ActionText)
        return action == "take" or action == "pickup" or action == "pick" or action == "collect"
            or action == "grab" or action == "pegar" or action == "coletar"
    end

    function World.fruitPromptName(prompt)
        if not World.isTakePrompt(prompt) then return nil end
        local label = tostring(prompt.ObjectText or ""):gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
        local known = World.fruitAlias(label)
        if known then return known end
        -- Mesmo que uma fruta nova ainda nao esteja no catalogo, o prompt [Take]
        -- com ObjectText terminando em Fruit e suficiente para identificacao.
        if label:lower():match("^[%w%s%-_]+%s+[Ff][Rr][Uu][Ii][Tt]$")
            and #label <= 45 then return label end
        return nil
    end

    function World.fruitDisplay(object)
        if not object or not object.Parent then return nil end
        local direct = World.fruitAlias(object.Name)
        if direct then return direct end
        if object:IsA("ProximityPrompt") then return World.fruitPromptName(object) end
        local label = fruitLabels[object]
        if label and label.Parent and label:IsDescendantOf(object) then
            local name = World.fruitAlias(label.Text)
            if name then return name end
        end
        if not (object:IsA("Tool") or object:IsA("BasePart")
            or (object:IsA("Model") and (object.PrimaryPart or object:FindFirstChild("Handle")))) then return nil end
        local stack, visited = {{object, 0}}, 0
        while #stack > 0 and visited < 65 do
            local item = table.remove(stack)
            local child, depth = item[1], item[2]
            visited = visited + 1
            if child:IsA("ProximityPrompt") and depth <= 3 then
                local name = World.fruitPromptName(child)
                if name then return name end
            elseif child:IsA("TextLabel") and child:FindFirstAncestorWhichIsA("BillboardGui") then
                local name = World.fruitAlias(child.Text)
                if name then fruitLabels[object] = child; return name end
            end
            if depth < 4 then
                for _, nextChild in ipairs(child:GetChildren()) do
                    if not nextChild:IsA("Model") and not nextChild:IsA("Tool") then
                        stack[#stack + 1] = {nextChild, depth + 1}
                    end
                end
            end
        end
    end

    function World.fruitPickup(object)
        if not object or not object.Parent then return nil end
        if object:FindFirstAncestorWhichIsA("Camera") or object:FindFirstAncestorWhichIsA("WorldModel") then return nil end
        local tool = object:IsA("Tool") and object or object:FindFirstAncestorWhichIsA("Tool")
        if tool then return World.fruitDisplay(tool) and tool or nil end
        local node = object
        while node and node ~= workspace do
            if node:IsA("Camera") or node:IsA("WorldModel") then return nil end
            if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return nil end
            local lower = string.lower(tostring(node.Name))
            for _, word in ipairs({"dealer", "merchant", "vendor", "fruitshop", "stockshop"}) do
                if lower:find(word, 1, true) then return nil end
            end
            if (node:IsA("Model") or node:IsA("BasePart")) and World.fruitName(node.Name) then
                return node
            end
            node = node.Parent
        end
        -- O prompt pode ser o unico lugar que mostra o nome real do fruto.
        if object:IsA("ProximityPrompt") then
            if World.fruitPromptName(object) then
                local part = object:FindFirstAncestorWhichIsA("BasePart")
                if part and part:IsDescendantOf(workspace) then return part end
            end
            return nil
        end
        local part = object:IsA("BasePart") and object or object:FindFirstAncestorWhichIsA("BasePart")
        if part and World.fruitDisplay(part) then return part end
        if object:IsA("Model") and World.fruitDisplay(object) then return object end
    end

    function World.indexFruit(object)
        if not object or not object.Parent or not object:IsDescendantOf(workspace) then return end
        if not (object:IsA("Model") or object:IsA("Tool") or object:IsA("BasePart")
            or object:IsA("TextLabel") or object:IsA("ProximityPrompt") or object:IsA("TouchTransmitter") or object:IsA("ClickDetector")) then return end
        local pickup = World.fruitPickup(object)
        if pickup then World.fruits[pickup] = true end
        return pickup
    end

    function World.chestName(value)
        local name = string.lower(tostring(value or ""))
        return name:find("chest", 1, true) ~= nil or name:find("bau", 1, true) ~= nil
            or name:find("baú", 1, true) ~= nil or name:find("treasure", 1, true) ~= nil
    end

    function World.islandCandidate(object)
        if not object or not (object:IsA("Model") or object:IsA("Folder")) then return false end
        if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then return false end
        local name = string.lower(tostring(object.Name or ""))
        local compact = name:gsub("[^%w]", "")
        if compact == "islands" or compact == "mapislands" or compact == "islandfolder"
            or compact == "islandmodels" or compact == "islandspawns" then
            return false
        end
        if name:find("quest", 1, true) or name:find("npc", 1, true) or name:find("teleport", 1, true) then
            return false
        end
        if name:find("island", 1, true) or name:find("ilha", 1, true) or name:find("isla", 1, true) then
            return true
        end
        local parent = object.Parent
        local parentName = parent and string.lower(tostring(parent.Name or "")):gsub("[^%w]", "") or ""
        return object:IsA("Model") and (parentName == "islands" or parentName == "mapislands" or parentName == "islandfolder")
    end

    function World.islandPosition(island)
        if not island or not island.Parent or not island:IsDescendantOf(workspace) then return nil end
        local cached = World.islandPositions[island]
        if cached then return cached end
        local position
        if island:IsA("Model") then
            -- Model pivots are more stable than bounding boxes while StreamingEnabled is loading pieces.
            local okPivot, pivot = pcall(function() return island:GetPivot() end)
            if okPivot and pivot then position = pivot.Position end
            if not position then
                local ok, frame = pcall(function() return island:GetBoundingBox() end)
                if ok and frame then position = frame.Position end
            end
        elseif island:IsA("BasePart") then
            position = island.Position
        end
        if not position then
            local ok, descendants = pcall(function() return island:GetDescendants() end)
            if ok then
                local minX, minY, minZ = math.huge, math.huge, math.huge
                local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
                for _, object in ipairs(descendants) do
                    if object:IsA("BasePart") then
                        local point = object.Position
                        minX, minY, minZ = math.min(minX, point.X), math.min(minY, point.Y), math.min(minZ, point.Z)
                        maxX, maxY, maxZ = math.max(maxX, point.X), math.max(maxY, point.Y), math.max(maxZ, point.Z)
                    end
                end
                if minX < math.huge then
                    position = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
                end
            end
        end
        if position then World.islandPositions[island] = position end
        return position
    end

    function World.islandFor(object)
        local node = object
        while node and node ~= workspace do
            if World.islands[node] then return node end
            node = node.Parent
        end
        return nil
    end

    function World.held(object)
        local node = object.Parent
        while node and node ~= workspace do
            if node:IsA("Backpack") or (node:IsA("Model") and node:FindFirstChildOfClass("Humanoid")) then return true end
            node = node.Parent
        end
        return false
    end

    function World.indexSummonDrop(object)
        local name = string.lower(tostring(object.Name)):gsub("[^%w]", "")
        local candidate = object
        if object:IsA("ProximityPrompt") then
            name = string.lower(tostring(object.ObjectText)):gsub("[^%w]", "")
            candidate = object:FindFirstAncestorWhichIsA("Tool") or object:FindFirstAncestorWhichIsA("Model")
        elseif not (object:IsA("Tool") or object:IsA("Model") or object:IsA("BasePart")) then return end
        if candidate and WorldBoss.DropKeys[name] and not World.held(candidate) then WorldBoss.Drops[candidate] = name end
    end

    function World.add(object)
        if destroyed or not object.Parent or object:IsDescendantOf(ScreenGui) or object:FindFirstAncestor("FlyToggle") then return end
        if World.onQuestObjectChanged then World.onQuestObjectChanged(object, false) end
        if World.onFruitShopGuiChanged then World.onFruitShopGuiChanged(object) end
        local inWorld = object:IsDescendantOf(workspace)
        local playerGui = object:FindFirstAncestorWhichIsA("PlayerGui")
        if inWorld then invalidateMobValidation(object) end
        if inWorld and World.islandCandidate(object) and not World.islands[object] then
            World.islands[object] = true
            World.islandRevision = World.islandRevision + 1
        end
        if inWorld and object:IsA("Humanoid") and not World.humanoids[object] then
            World.humanoids[object] = true
            World.revision = World.revision + 1
        end
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            if inWorld or playerGui then World.texts[object] = true end
        end
        if playerGui and (object:IsA("TextLabel") or object:IsA("TextBox") or object:IsA("GuiButton")) then
            World.gui[object] = true
        elseif object:IsDescendantOf(LocalPlayer) and not playerGui and not object:FindFirstAncestorWhichIsA("Backpack") then
            World.stats[object] = true
        end
        if not inWorld then return end
        if object:IsA("ProximityPrompt") then World.prompts[object] = true end
        World.indexFruit(object)
        World.indexSummonDrop(object)
        if World.onFruitAdded then World.onFruitAdded(object) end
        if World.onVisualAdded then World.onVisualAdded(object) end
        if (object:IsA("Model") or object:IsA("BasePart")) and World.chestName(object.Name) then
            World.chests[object] = true
        end
    end

    function World.remove(object)
        if World.onFarmMobRemoved then World.onFarmMobRemoved(object) end
        if World.onQuestObjectChanged then World.onQuestObjectChanged(object, true) end
        if World.onFruitShopGuiChanged then World.onFruitShopGuiChanged(object) end
        if World.onFruitRemoved then World.onFruitRemoved(object) end
        if object.Parent and object:IsDescendantOf(workspace) then invalidateMobValidation(object) end
        if World.humanoids[object] then World.revision = World.revision + 1 end
        if World.islands[object] then
            World.islands[object] = nil
            World.islandPositions[object] = nil
            World.islandRevision = World.islandRevision + 1
        end
        World.humanoids[object], World.texts[object], World.gui[object], World.prompts[object] = nil, nil, nil, nil
        World.fruits[object], World.chests[object], World.stats[object] = nil, nil, nil
        WorldBoss.Drops[object] = nil
    end

    connect(workspace.DescendantAdded, World.add)
    connect(workspace.DescendantRemoving, World.remove)
    connect(LocalPlayer.DescendantAdded, World.add)
    connect(LocalPlayer.DescendantRemoving, World.remove)
    local indexThread = task.spawn(function()
        local processed = 0
        for _, container in ipairs({workspace, LocalPlayer}) do
            local stack = container:GetChildren()
            while #stack > 0 do
                if destroyed then return end
                local object = stack[#stack]
                stack[#stack] = nil
                World.add(object)
                local children = object:GetChildren()
                for _, child in ipairs(children) do
                    stack[#stack + 1] = child
                end
                processed = processed + 1
                if processed % 300 == 0 then task.wait() end
            end
        end
        World.ready = true
    end)

    function World.liveMob(model)
        if not model or not model.Parent or not model:IsA("Model") or not model:IsDescendantOf(workspace)
            or model == LocalPlayer.Character or Players:GetPlayerFromCharacter(model) then return false end
        local humanoid, root = getMobHumanoid(model), getMobRoot(model)
        return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
    end

    local invalidMobNameHints = {"quest", "npc", "vendor", "merchant", "shopkeeper", "blacksmith", "mission", "trainer"}
    local healthHints = {"health", "hpbar", "hp_bar", "hitpoint", "hit_point", "vida", "life_bar", "lifebar"}

    isValidFarmMob = function(model)
        if not World.liveMob(model) then return false end
        local saved, now = validation[model], os.clock()
        if saved and now < saved.expires then return saved.valid end
        local name = string.lower(model.Name)
        local valid = true
        for _, hint in ipairs(invalidMobNameHints) do
            if name:find(hint, 1, true) then valid = false; break end
        end
        if valid then
            local humanoid = getMobHumanoid(model)
            local ok, healthShown = pcall(function()
                return humanoid.MaxHealth > 0 and humanoid.HealthDisplayDistance > 0
                    and humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None
                    and (humanoid.HealthDisplayType == Enum.HumanoidHealthDisplayType.AlwaysOn
                        or (humanoid.HealthDisplayType == Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
                            and humanoid.Health < humanoid.MaxHealth))
            end)
            healthShown = ok and healthShown
            for _, object in ipairs(model:GetDescendants()) do
                if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then valid = false; break end
                local objectName = string.lower(object.Name)
                local textValue = object:IsA("TextLabel") and object.Text or ""
                local textLower = textValue ~= "" and string.lower(textValue) or ""
                local likelyHealth = false
                for _, hint in ipairs(healthHints) do
                    if objectName:find(hint, 1, true) or (textLower ~= "" and textLower:find(hint, 1, true)) then
                        likelyHealth = true
                        break
                    end
                end
                if not likelyHealth then
                    likelyHealth = objectName:match("%d+%s*/%s*%d+") ~= nil or objectName:match("%d+%%") ~= nil
                    if not likelyHealth and textLower ~= "" then
                        likelyHealth = textLower:match("%d+%s*/%s*%d+") ~= nil or textLower:match("%d+%%") ~= nil
                    end
                end
                if likelyHealth then
                    local board = object:IsA("BillboardGui") and object or object:FindFirstAncestorWhichIsA("BillboardGui")
                    if board and board.Enabled then healthShown = true; break end
                end
            end
            valid = valid and healthShown == true
        end
        validation[model] = {valid = valid, expires = now + 6 + math.random() * 3}
        return valid
    end

    collectFarmMobTypes = function()
        local names, result = {}, {}
        for humanoid in pairs(World.humanoids) do
            local model = humanoid.Parent
            if isValidFarmMob(model) then names[model.Name] = true end
        end
        for name in pairs(names) do result[#result + 1] = name end
        table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
        return result
    end

    function Motion.character()
        if World.characterUnavailable then return end
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if character and character.Parent and root and humanoid and humanoid.Health > 0 then return character, root, humanoid end
    end

    function Motion.releaseAim()
        Motion.aimPoint = nil
        local saved = Motion.farmView
        Motion.farmView = nil
        if not saved then return end
        pcall(function()
            local subject = saved.subject
            if not subject or not subject.Parent then
                local character = LocalPlayer.Character
                subject = character and character:FindFirstChildOfClass("Humanoid")
            end
            if subject then saved.camera.CameraSubject = subject end
            saved.camera.CameraType = saved.cameraType
        end)
        pcall(function()
            if saved.mouseBehavior ~= nil then UserInputService.MouseBehavior = saved.mouseBehavior end
        end)
    end

    function Motion.cancelLongTravel(owner)
        local job = Motion.longTravel
        if not job or (owner and job.owner ~= owner) then return end
        job.cancelled = true
        Motion.longTravel = nil
        TeleportLoading.cancelOwner("auto:" .. tostring(job.owner))
    end

    function Landing.releaseSpace()
        if Landing.spaceDown and VirtualInputManager then
            pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end
        Landing.spaceDown, Landing.releaseAt = false, nil
    end

    function Landing.clear()
        Landing.pending = nil
        Landing.releaseSpace()
    end

    function Landing.height(character, root, humanoid)
        local halfRoot = (tonumber(root.Size.Y) or 2) * 0.5
        local height = math.max(0, tonumber(humanoid.HipHeight) or 0) + halfRoot
        if humanoid.RigType == Enum.HumanoidRigType.R6 then
            local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
            if leg and leg:IsA("BasePart") then height = height + (tonumber(leg.Size.Y) or 0) end
        end
        return height
    end

    function Landing.parameters(character)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignored, target = {character}, Motion.target
        if target and target.Parent then
            local model = target:IsA("Model") and target or target:FindFirstAncestorWhichIsA("Model")
            if model and (model:FindFirstChildOfClass("Humanoid") or World.chestName(model.Name)) then target = model end
            ignored[#ignored + 1] = target
        end
        params.FilterDescendantsInstances = ignored
        params.IgnoreWater, params.RespectCanCollide = false, true
        return params
    end

    function Landing.floor(position, height, params)
        local lift = math.max(3, math.min(height + 0.5, 8))
        local hit = workspace:Raycast(position + Vector3.new(0, lift, 0), Vector3.new(0, -(lift + height + 12), 0), params)
        if not hit or hit.Material == Enum.Material.Water or (hit.Normal and hit.Normal.Y < 0.5) then return nil end
        return hit.Position.Y
    end

    function Landing.combatPose()
        return (Motion.owner == "Farm" or Motion.owner == "Quest" or Motion.owner == "Swords") and Motion.kind == "mob"
    end

    function Landing.destination(character, root, destination)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 or Landing.combatPose() then return destination end
        local height = Landing.height(character, root, humanoid)
        local floor = Landing.floor(destination.Position, height, Landing.parameters(character))
        if floor then
            local correction = floor + height + 0.35 - destination.Position.Y
            if correction > 0.05 and correction <= height * 2 + 1 then
                return destination + Vector3.new(0, correction, 0)
            end
        end
        return destination
    end

    function Landing.watch(character, root, destination, origin)
        if Landing.combatPose() then Landing.clear(); return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 or ManualFlight.Enabled then return end
        local pending, now = Landing.pending, os.clock()
        if pending and pending.root == root and SafeMode.flatDistance(pending.destination, destination.Position) < 4 then
            pending.destination = destination.Position
            return
        end
        if (destination.Position - origin).Magnitude < 0.5 then return end
        Landing.clear()
        Landing.pending = {character = character, root = root, humanoid = humanoid,
            destination = destination.Position, position = root.Position, height = Landing.height(character, root, humanoid),
            params = Landing.parameters(character), startedAt = now, nextCheckAt = now + 0.18,
            expiresAt = now + 3, attempts = 0}
    end

    function Landing.step()
        local now = os.clock()
        if Landing.releaseAt and now >= Landing.releaseAt then Landing.releaseSpace() end
        local pending = Landing.pending
        if not pending then return end
        local character, root, humanoid = Motion.character()
        if destroyed or ManualFlight.Enabled or character ~= pending.character or root ~= pending.root
            or humanoid ~= pending.humanoid or humanoid.PlatformStand or now >= pending.expiresAt then
            Landing.clear()
            return
        end
        if now < pending.nextCheckAt then return end
        pending.nextCheckAt = now + 0.15
        if (root.Position - pending.destination).Magnitude > 18 then Landing.clear(); return end
        local displacement = SafeMode.flatDistance(root.Position, pending.position)
        if displacement > 1 then pending.position, pending.startedAt = root.Position, now end
        local floor = Landing.floor(root.Position, pending.height, pending.params)
        if not floor then return end
        local buried = floor + pending.height - root.Position.Y > 0.65
        local blocked = displacement < 0.5 and now - pending.startedAt > 0.7
            and humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
        if not buried and not blocked then return end
        if pending.attempts >= 2 or now < (pending.nextJumpAt or 0) then return end
        if UserInputService:GetFocusedTextBox() then return end
        pending.attempts, pending.nextJumpAt = pending.attempts + 1, now + 0.85
        local manualSpace = false
        pcall(function() manualSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space) end)
        if VirtualInputManager and not manualSpace then
            local sent = pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game) end)
            if sent then Landing.spaceDown, Landing.releaseAt = true, now + 0.1 end
        end
        humanoid.Jump = true
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end

    SafeMode.heldKeys = {}
    SafeMode.dashDistance, SafeMode.dashInterval = 15, 0.6
    SafeMode.windowFocused = true
    SafeMode.directionKeys = {Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D}

    function SafeMode.keyDown(key)
        local ok, down = pcall(function() return UserInputService:IsKeyDown(key) end)
        return ok and down == true
    end

    function SafeMode.key(key, down)
        if down and SafeMode.heldKeys[key] then return true end
        if not down and not SafeMode.heldKeys[key] then return true end
        if down and SafeMode.keyDown(key) then return false end
        local ok = VirtualInputManager and pcall(function()
            VirtualInputManager:SendKeyEvent(down, key, false, game)
        end)
        if down then
            if ok then SafeMode.heldKeys[key] = true end
        else
            if not ok and VirtualInputManager then
                pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
            end
            SafeMode.heldKeys[key] = nil
        end
        return ok == true
    end

    function SafeMode.stopKeys(nav, preserveRecovery)
        SafeMode.key(Enum.KeyCode.Q, false)
        if not preserveRecovery then
            SafeMode.key(Enum.KeyCode.Space, false)
            SafeMode.recovery = nil
        end
        for _, key in ipairs(SafeMode.directionKeys) do SafeMode.key(key, false) end
        SafeMode.dashReleaseAt = nil
        if nav then
            nav.desiredKeys, nav.movingSince, nav.directionAt = nil, nil, nil
            nav.dashKeys, nav.dashUntil = nil, nil
        end
    end

    function SafeMode.inputPaused()
        if not SafeMode.windowFocused or UserInputService:GetFocusedTextBox() then return true end
        for _, key in ipairs(SafeMode.directionKeys) do
            if not SafeMode.heldKeys[key] and SafeMode.keyDown(key) then return true end
        end
        return false
    end

    function SafeMode.tickKeys()
        local now, nav = os.clock(), SafeMode.nav
        if SafeMode.dashReleaseAt and now >= SafeMode.dashReleaseAt then
            SafeMode.key(Enum.KeyCode.Q, false)
            SafeMode.dashReleaseAt = nil
        end
        if destroyed or not SafeMode.Enabled or not nav or not SafeMode.valid(nav)
            or SafeMode.inputPaused() then SafeMode.stopKeys(nav); return end
        SafeMode.tickRecovery(nav, now)
    end

    function SafeMode.cameraAxes()
        local camera = workspace.CurrentCamera
        if not camera then return nil end
        local look = camera.CFrame.LookVector
        local forward = Vector3.new(look.X, 0, look.Z)
        if forward.Magnitude < 0.05 then
            local right = camera.CFrame.RightVector
            forward = Vector3.new(right.Z, 0, -right.X)
        end
        if forward.Magnitude < 0.05 then return nil end
        forward = forward.Unit
        return forward, Vector3.new(-forward.Z, 0, forward.X)
    end

    function SafeMode.startRecovery(nav, now)
        if SafeMode.recovery or now < (nav.nextRecoveryAt or 0) or (nav.recoveryAttempts or 0) >= 3
            or Landing.spaceDown or SafeMode.inputPaused() or SafeMode.keyDown(Enum.KeyCode.Space)
            or (nav.dashUntil and now < nav.dashUntil) then return end
        nav.nextRecoveryAt = now + 2.5
        if not SafeMode.key(Enum.KeyCode.Space, true) then return end
        nav.recoveryAttempts = (nav.recoveryAttempts or 0) + 1
        nav.dashKeys, nav.dashUntil = nil, nil
        nav.humanoid.Jump = true
        SafeMode.recovery = {nav = nav, phase = 1, releaseAt = now + 0.025, secondAt = now + 0.1}
    end

    function SafeMode.tickRecovery(nav, now)
        local recovery = SafeMode.recovery
        if not recovery then return end
        if recovery.nav ~= nav or Landing.spaceDown
            or (Motion.kind == "mob" and not World.liveMob(Motion.target)) then
            SafeMode.key(Enum.KeyCode.Space, false)
            SafeMode.recovery = nil
            return
        end
        if recovery.releaseAt and now >= recovery.releaseAt then
            SafeMode.key(Enum.KeyCode.Space, false)
            recovery.releaseAt = nil
            if recovery.phase == 2 then SafeMode.recovery = nil; return end
        end
        if recovery.phase == 1 and now >= recovery.secondAt then
            if SafeMode.keyDown(Enum.KeyCode.Space) or not SafeMode.key(Enum.KeyCode.Space, true) then
                SafeMode.recovery = nil
                return
            end
            nav.humanoid.Jump = true
            recovery.phase, recovery.releaseAt = 2, now + 0.025
        end
    end

    function SafeMode.steer(nav, point, now)
        if SafeMode.inputPaused() or now < (SafeMode.inputRetryAt or 0) then SafeMode.stopKeys(nav); return false end
        local delta = point - nav.root.Position
        local direction = Vector3.new(delta.X, 0, delta.Z)
        local forward, right = SafeMode.cameraAxes()
        if not forward or direction.Magnitude < 0.2 then SafeMode.stopKeys(nav); return false end
        direction = direction.Unit
        local old, desired = nav.desiredKeys or {}, {}
        local along, across = direction:Dot(forward), direction:Dot(right)
        local function choose(key, value)
            if value > (old[key] and 0.32 or 0.43) then desired[key] = true end
        end
        if nav.dashKeys and nav.dashUntil and now < nav.dashUntil then
            for _, key in ipairs(SafeMode.directionKeys) do desired[key] = nav.dashKeys[key] end
        else
            choose(Enum.KeyCode.W, along); choose(Enum.KeyCode.S, -along)
            choose(Enum.KeyCode.D, across); choose(Enum.KeyCode.A, -across)
        end
        local changed = false
        for _, key in ipairs(SafeMode.directionKeys) do
            if (old[key] == true) ~= (desired[key] == true) then changed = true end
        end
        for _, key in ipairs(SafeMode.directionKeys) do
            if not desired[key] then SafeMode.key(key, false) end
        end
        for _, key in ipairs(SafeMode.directionKeys) do
            if desired[key] and not SafeMode.key(key, true) then
                SafeMode.inputRetryAt = now + 1
                SafeMode.stopKeys(nav)
                return false
            end
        end
        SafeMode.inputRetryAt = 0
        if changed or not nav.directionAt then nav.directionAt = now end
        nav.desiredKeys, nav.command, nav.movingSince = desired, point, nav.movingSince or now
        return true
    end

    function SafeMode.dash(nav, now)
        local part = Motion.kind == "mob" and World.root(Motion.target)
        local destination = part and part.Position or (Motion.kind == "point" and Motion.destination)
        local validDestination = typeof(destination) == "Vector3"
            and (Motion.kind == "point" or World.liveMob(Motion.target))
        if not validDestination or SafeMode.flatDistance(nav.root.Position, destination) <= SafeMode.dashDistance then
            local wasLocked = nav.dashUntil
            SafeMode.key(Enum.KeyCode.Q, false)
            SafeMode.dashReleaseAt = nil
            nav.dashKeys, nav.dashUntil = nil, nil
            if wasLocked and nav.command then SafeMode.steer(nav, nav.command, now) end
            return
        end
        if nav.dashUntil then
            if now < nav.dashUntil then return end
            nav.dashKeys, nav.dashUntil = nil, nil
        end
        if (Motion.owner ~= "Farm" and Motion.owner ~= "Swords") or not validDestination
            or now < (SafeMode.nextDashAt or 0) or not nav.movingSince or now - nav.movingSince < 0.15
            or QuestRuntime.SkillBusy or QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving
            or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy or Landing.spaceDown or SafeMode.recovery
            or nav.humanoid.FloorMaterial == Enum.Material.Air or SafeMode.inputPaused()
            or SafeMode.keyDown(Enum.KeyCode.Q) or now - (nav.directionAt or now) < 0.05 then return end
        local forward, right = SafeMode.cameraAxes()
        if not forward then return end
        local delta = destination - nav.root.Position
        local toward = Vector3.new(delta.X, 0, delta.Z)
        local route = (nav.command or destination) - nav.root.Position
        route = Vector3.new(route.X, 0, route.Z)
        if route.Magnitude < 0.2 or route.Unit:Dot(toward.Unit) < 0.65 then return end
        local desired, keys = nav.desiredKeys or {}, {}
        for _, key in ipairs(SafeMode.directionKeys) do
            if desired[key] then
                if not SafeMode.heldKeys[key] then return end
                keys[key] = true
            end
        end
        local along = (keys[Enum.KeyCode.W] and 1 or 0) - (keys[Enum.KeyCode.S] and 1 or 0)
        local across = (keys[Enum.KeyCode.D] and 1 or 0) - (keys[Enum.KeyCode.A] and 1 or 0)
        local movement = forward * along + right * across
        if movement.Magnitude < 0.1 or movement.Unit:Dot(route.Unit) < 0.85
            or not SafeMode.clearLine(nav, nav.root.Position + movement.Unit * 12) then return end
        SafeMode.nextDashAt = now + SafeMode.dashInterval
        if SafeMode.key(Enum.KeyCode.Q, true) then
            nav.dashKeys = keys
            SafeMode.dashReleaseAt, nav.dashUntil = now + 0.1, now + 0.35
            nav.dashRouteOrigin, nav.dashRouteMoved = nav.root.Position, 0
        end
    end

    if UserInputService.TextBoxFocused then
        connect(UserInputService.TextBoxFocused, function() SafeMode.stopKeys(SafeMode.nav) end)
    end
    if UserInputService.WindowFocusReleased then
        connect(UserInputService.WindowFocusReleased, function()
            SafeMode.windowFocused = false
            SafeMode.stopKeys(SafeMode.nav)
        end)
    end
    if UserInputService.WindowFocused then
        connect(UserInputService.WindowFocused, function() SafeMode.windowFocused = true end)
    end

    function SafeMode.walkSpeed(humanoid)
        if not humanoid then
            local character = LocalPlayer.Character
            humanoid = character and character:FindFirstChildOfClass("Humanoid")
        end
        local speed = humanoid and tonumber(humanoid.WalkSpeed) or 0
        return speed and speed > 0 and speed < math.huge and speed or 0
    end

    function SafeMode.flatDistance(a, b)
        local delta = a - b
        return Vector3.new(delta.X, 0, delta.Z).Magnitude
    end

    function SafeMode.isTravelPoint(point)
        for _, entry in ipairs(World.travelPoints or {}) do
            if point == entry then return true end
        end
        return false
    end

    function SafeMode.nearestIsland(position)
        local closest, distance = nil, math.huge
        for _, point in ipairs(World.travelPoints or {}) do
            local candidate = SafeMode.flatDistance(position, point.position)
            if candidate < distance then closest, distance = point, candidate end
        end
        return closest, distance
    end

    function SafeMode.dropPath(nav)
        if nav.pathConnection then nav.pathConnection:Disconnect(); nav.pathConnection = nil end
        if nav.path then pcall(function() nav.path:Destroy() end); nav.path = nil end
        nav.waypoints, nav.waypointIndex, nav.jumpedIndex = nil, nil, nil
    end

    function SafeMode.clear()
        local nav = SafeMode.nav
        SafeMode.stopKeys(nav)
        SafeMode.nav = nil
        if not nav then return end
        nav.cancelled = true
        if nav.pathThread then pcall(task.cancel, nav.pathThread) end
        if nav.islandThread then pcall(task.cancel, nav.islandThread) end
        if nav.pendingPath then pcall(function() nav.pendingPath:Destroy() end) end
        TeleportLoading.cancelOwner("safe-island")
        SafeMode.dropPath(nav)
    end

    function SafeMode.valid(nav)
        return SafeMode.Enabled and not destroyed and SafeMode.nav == nav and not nav.cancelled
            and nav.root.Parent ~= nil and nav.humanoid.Parent ~= nil and nav.humanoid.Health > 0
            and Motion.root == nav.root and Motion.owner == nav.owner
            and Motion.allowed(nav.owner) and os.clock() <= (Motion.lease or 0)
    end

    function SafeMode.ground(nav, position, depth)
        local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -(depth or 80), 0), nav.raycast)
        if not hit or hit.Material == Enum.Material.Water then return nil, hit end
        return hit.Position + Vector3.new(0, nav.humanoid.HipHeight + nav.root.Size.Y * 0.5, 0), hit
    end

    function SafeMode.otherIsland(nav, position, target, now)
        if now < (nav.nextIslandCheck or 0) then return nav.requiredIsland end
        nav.nextIslandCheck = now + 0.75
        nav.requiredIsland = nil
        if SafeMode.flatDistance(nav.root.Position, position) < 650 then return nil end
        local origin = SafeMode.nearestIsland(nav.root.Position)
        local destination, destinationDistance = SafeMode.nearestIsland(position)
        if not origin or not destination or origin == destination or destinationDistance > 1800 then return nil end
        local _, originGround = SafeMode.ground(nav, nav.root.Position, 40)
        local _, targetGround = SafeMode.ground(nav, position)
        local originModel = originGround and originGround.Instance and World.islandFor(originGround.Instance)
        local targetModel = World.islandFor(target) or (targetGround and targetGround.Instance and World.islandFor(targetGround.Instance))
        if originModel and originModel == targetModel then return nil end
        if SafeMode.flatDistance(nav.root.Position, destination.position) <= destinationDistance + 300 then return nil end
        nav.requiredIsland = destination
        return destination
    end

    function SafeMode.transfer(nav, point, now)
        if nav.islandPending then return end
        if nav.lastIsland == point and now - (nav.lastIslandAt or 0) < 12 then return end
        if nav.lastIsland == point and (nav.islandAttempts or 0) >= 2 then return end
        nav.islandAttempts = nav.lastIsland == point and (nav.islandAttempts or 0) + 1 or 1
        nav.lastIsland, nav.lastIslandAt = point, now
        nav.islandPending = true
        SafeMode.stopKeys(nav)
        SafeMode.dropPath(nav)
        if nav.pathThread then pcall(task.cancel, nav.pathThread); nav.pathThread = nil end
        if nav.pendingPath then pcall(function() nav.pendingPath:Destroy() end); nav.pendingPath = nil end
        nav.computing = false
        local worker = task.spawn(function()
            pcall(Motion.travelIsland, point, function()
                return SafeMode.valid(nav) and SafeMode.walkSpeed(nav.humanoid) > 0
                    and not nav.humanoid.Sit and not nav.humanoid.PlatformStand
            end, "safe-island")
            if not SafeMode.valid(nav) then return end
            nav.islandPending, nav.islandThread = false, nil
            nav.lastPosition, nav.progressAt = nav.root.Position, os.clock()
            nav.nextIslandCheck, nav.requiredIsland = 0, nil
            nav.pathGoal, nav.nextPathAt, nav.nextCommandAt = nil, 0, 0
        end)
        if nav.islandPending then nav.islandThread = worker end
    end

    function SafeMode.compute(nav, goal, now)
        if nav.computing or now < (nav.nextPathAt or 0) then return end
        nav.nextPathAt, nav.computing, nav.pathGoal = now + 1, true, goal
        local revision = nav.routeRevision or 0
        local worker = task.spawn(function()
            local path
            local ok = pcall(function()
                path = game:GetService("PathfindingService"):CreatePath({
                    AgentRadius = math.max(2, nav.root.Size.X * 0.5 + 0.5),
                    AgentHeight = math.max(5, nav.humanoid.HipHeight * 2 + nav.root.Size.Y),
                    AgentCanJump = true, WaypointSpacing = 5, Costs = {Water = math.huge},
                })
                nav.pendingPath = path
                path:ComputeAsync(nav.root.Position, goal)
            end)
            if not SafeMode.valid(nav) or nav.pendingPath ~= path then
                if path then pcall(function() path:Destroy() end) end
                return
            end
            nav.computing, nav.pathThread, nav.pendingPath = false, nil, nil
            if revision ~= (nav.routeRevision or 0) then
                if path then pcall(function() path:Destroy() end) end
                nav.repath = true
                return
            end
            if ok and path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                if #waypoints > 0 then
                    SafeMode.dropPath(nav)
                    nav.path, nav.waypoints, nav.waypointIndex = path, waypoints, 1
                    nav.repath, nav.nextCommandAt = false, 0
                    nav.pathConnection = path.Blocked:Connect(function(index)
                        if SafeMode.valid(nav) and index >= (nav.waypointIndex or 1) then nav.repath = true end
                    end)
                    return
                end
            end
            if path then pcall(function() path:Destroy() end) end
            SafeMode.dropPath(nav)
            nav.repath = true
            SafeMode.stopKeys(nav)
        end)
        if nav.computing then nav.pathThread = worker end
    end

    function SafeMode.clearLine(nav, goal)
        local delta = goal - nav.root.Position
        if delta.Magnitude > 14 or math.abs(delta.Y) > 4 then return false end
        if workspace:Raycast(nav.root.Position, delta, nav.raycast) then return false end
        local steps = math.max(1, math.ceil(SafeMode.flatDistance(goal, nav.root.Position) / 4))
        for index = 1, steps do
            if not SafeMode.ground(nav, nav.root.Position + delta * (index / steps), 15) then return false end
        end
        return true
    end

    function SafeMode.refreshDashRoute(nav, now)
        if not nav.dashRouteOrigin then return end
        local origin = nav.dashRouteOrigin
        local moved = math.max(nav.dashRouteMoved or 0, SafeMode.flatDistance(origin, nav.root.Position))
        nav.dashRouteMoved = moved
        if nav.dashUntil and now < nav.dashUntil then return end
        nav.dashRouteOrigin, nav.dashRouteMoved = nil, nil
        if moved <= 2.5 then return end
        local travelled = nav.root.Position - origin
        travelled = Vector3.new(travelled.X, 0, travelled.Z)
        if nav.waypoints and not nav.repath and not nav.computing and travelled.Magnitude >= moved * 0.8 then
            SafeMode.advancePath(nav)
            local point = nav.waypoints[nav.waypointIndex]
            if point and math.abs(point.Position.Y - nav.root.Position.Y) <= 4 then
                local ahead = point.Position - nav.root.Position
                ahead = Vector3.new(ahead.X, 0, ahead.Z)
                if ahead:Dot(travelled) >= 0 then nav.command = nil; return end
            end
        end
        nav.routeRevision = (nav.routeRevision or 0) + 1
        SafeMode.dropPath(nav)
        nav.repath = true
        nav.pathGoal, nav.command, nav.stageGoal, nav.stageTarget = nil, nil, nil, nil
        nav.nextPathAt, nav.lastPosition, nav.progressAt = math.max(now, nav.nextPathAt or now), nav.root.Position, now
    end

    function SafeMode.advancePath(nav)
        local points, index = nav.waypoints, nav.waypointIndex or 1
        if not points then return end
        while index <= #points do
            local point = points[index]
            if point.Action == Enum.PathWaypointAction.Jump and nav.jumpedIndex ~= index then break end
            local offset = nav.root.Position - point.Position
            if math.abs(offset.Y) > 4 then break end
            if SafeMode.flatDistance(nav.root.Position, point.Position) > 2.5 then
                local following = points[index + 1]
                if not following or math.abs(following.Position.Y - point.Position.Y) > 4 then break end
                local edge = following.Position - point.Position
                edge = Vector3.new(edge.X, 0, edge.Z)
                local flat = Vector3.new(offset.X, 0, offset.Z)
                local lengthSquared = edge:Dot(edge)
                if lengthSquared < 0.01 then break end
                local progress = flat:Dot(edge) / lengthSquared
                if progress < 0 or (flat - edge * progress).Magnitude > 2.5
                    or not SafeMode.clearLine(nav, following.Position) then break end
            end
            index = index + 1
        end
        nav.waypointIndex = index
    end

    function SafeMode.step(character, root, humanoid, targetPosition, destination, now)
        local nav = SafeMode.nav
        if not nav or nav.root ~= root or nav.owner ~= Motion.owner then
            SafeMode.clear()
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local obstacle = Motion.target
            if obstacle and not obstacle:IsA("Model") then
                local model = obstacle:FindFirstAncestorWhichIsA("Model")
                if model and (model:FindFirstChildOfClass("Humanoid") or World.chestName(model.Name)) then obstacle = model end
            end
            params.FilterDescendantsInstances = obstacle and {character, obstacle} or {character}
            params.IgnoreWater, params.RespectCanCollide = false, true
            nav = {root = root, humanoid = humanoid, owner = Motion.owner,
                raycast = params, lastPosition = root.Position, progressAt = now, nextPathAt = 0, nextCommandAt = 0}
            SafeMode.nav = nav
        end
        Motion.mode, QuestRuntime.AimTarget = "WALK", nil
        if SafeMode.walkSpeed(humanoid) == 0 or humanoid.Sit or humanoid.PlatformStand or SafeMode.inputPaused() then
            nav.progressAt, nav.lastPosition = now, root.Position
            SafeMode.stopKeys(nav)
            nav.paused = true
            Motion.arrived = false
            return
        elseif nav.paused then
            nav.paused, nav.nextCommandAt, nav.waiting = false, 0, false
        end
        SafeMode.refreshDashRoute(nav, now)
        if now >= (nav.nextBuriedAt or 0) then
            nav.nextBuriedAt = now + 0.3
            local stand = SafeMode.ground(nav, root.Position, 15)
            nav.buried = stand and stand.Y - root.Position.Y > 0.65 or false
        end
        if nav.buried then SafeMode.startRecovery(nav, now) end
        local island = SafeMode.otherIsland(nav, targetPosition, Motion.target, now)
        if island or nav.islandPending then
            Motion.arrived = false
            if island then SafeMode.transfer(nav, island, now) end
            return
        end
        if not nav.goal or SafeMode.flatDistance(nav.rawGoal, destination) > 2
            or math.abs(nav.rawGoal.Y - destination.Y) > 3 or now >= (nav.nextGroundAt or 0) then
            nav.goal = SafeMode.ground(nav, destination) or destination
            nav.rawGoal = destination
            nav.nextGroundAt = now + 0.5
        end
        local goal = nav.goal
        local distance = SafeMode.flatDistance(root.Position, goal)
        local tolerance = Motion.walkRange or (Motion.kind == "mob" and 1.5 or 1)
        local arrived = distance <= tolerance and math.abs(root.Position.Y - goal.Y) <= 4 and not nav.buried
        if arrived or (nav.arrived and not nav.buried and distance <= tolerance + 1.25 and math.abs(root.Position.Y - goal.Y) <= 4) then
            Motion.arrived, nav.arrived, nav.progressAt = true, true, now
            if not nav.stopped then
                SafeMode.stopKeys(nav)
                nav.stopped = true
                SafeMode.dropPath(nav)
                if nav.pathThread then pcall(task.cancel, nav.pathThread); nav.pathThread = nil end
                if nav.pendingPath then pcall(function() nav.pendingPath:Destroy() end); nav.pendingPath = nil end
                nav.computing = false
            end
            return
        end
        Motion.arrived, nav.arrived, nav.stopped = false, false, false
        if SafeMode.flatDistance(root.Position, nav.lastPosition) > 1 then
            nav.lastPosition, nav.progressAt = root.Position, now
            nav.recoveryAttempts = 0
        elseif now - nav.progressAt > 12 then
            if Motion.target then Motion.blocked[Motion.target] = now + 8 end
            Motion.release(nav.owner)
            return
        elseif now - nav.progressAt > 2 then
            nav.repath = true
        end
        if nav.command and not nav.waiting and now - nav.progressAt > 1.25 then SafeMode.startRecovery(nav, now) end
        local pathGoal = goal
        if distance > 500 then
            if not nav.stageGoal or SafeMode.flatDistance(root.Position, nav.stageGoal) < 18
                or SafeMode.flatDistance(goal, nav.stageTarget) > 35 then
                local offset = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
                local stage = root.Position + offset.Unit * 400
                nav.stageGoal, nav.stageTarget = SafeMode.ground(nav, stage) or stage, goal
            end
            pathGoal = nav.stageGoal
        else
            nav.stageGoal, nav.stageTarget = nil, nil
        end
        local movedGoal = not nav.pathGoal or SafeMode.flatDistance(nav.pathGoal, pathGoal) > 7
            or math.abs(nav.pathGoal.Y - pathGoal.Y) > 4
        if nav.repath or movedGoal or not nav.waypoints then SafeMode.compute(nav, pathGoal, now) end
        local command, jump
        if SafeMode.clearLine(nav, goal) then
            command = goal
        elseif nav.waypoints and not movedGoal then
            SafeMode.advancePath(nav)
            local point = nav.waypoints[nav.waypointIndex]
            if point then
                command, jump = point.Position, point.Action == Enum.PathWaypointAction.Jump
            else
                nav.repath = true
            end
        end
        if command then
            if jump and now >= (nav.nextJumpAt or 0) and humanoid.FloorMaterial ~= Enum.Material.Air then
                humanoid.Jump, nav.nextJumpAt = true, now + 0.8
                nav.jumpedIndex = nav.waypointIndex
            end
            if SafeMode.steer(nav, command, now) then SafeMode.dash(nav, now) end
        else
            SafeMode.stopKeys(nav, true)
        end
        nav.waiting = command == nil
    end

    function Motion.walkTo(owner, destination, target, valid, range)
        local _, root = Motion.character()
        if not root then return false end
        local deadline = os.clock() + math.clamp((root.Position - destination).Magnitude / math.max(1, SafeMode.walkSpeed()) + 60, 45, 600)
        while SafeMode.Enabled and not destroyed and valid() and os.clock() < deadline do
            local _, currentRoot = Motion.character()
            if currentRoot ~= root then break end
            local part = target and World.root(target)
            local spacing = part and SafeMode.flatDistance(destination, part.Position) or 0
            if not Motion.request(owner, target, spacing, target and "giver" or "point", destination) then return false end
            Motion.walkRange = range or 2
            if Motion.arrived and Motion.root == root then Motion.release(owner); return true end
            task.wait(0.2)
        end
        if Motion.owner == owner then Motion.release(owner) end
        return false
    end

    function SafeMode.setEnabled(state)
        state = state == true
        if SafeMode.Enabled == state then return end
        SafeMode.Enabled = state
        Motion.cancelManual()
        Motion.manualUntil = 0
        Motion.release()
        if QuestRuntime.StopItems then QuestRuntime.StopItems() end
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
    end

    function Motion.release(owner)
        if owner and Motion.owner ~= owner then return end
        Landing.clear()
        SafeMode.clear()
        Motion.cancelLongTravel()
        Motion.releaseAim()
        Motion.streamToken = (Motion.streamToken or 0) + 1
        if Motion.streamThread then pcall(task.cancel, Motion.streamThread); Motion.streamThread = nil end
        if Motion.streamRequestThread then pcall(task.cancel, Motion.streamRequestThread); Motion.streamRequestThread = nil end
        Motion.streamPending, Motion.streamReady, Motion.streamPosition = false, false, nil
        Motion.streamStartedAt = nil
        if Motion.velocity then Motion.velocity:Destroy(); Motion.velocity = nil end
        if Motion.attachment then Motion.attachment:Destroy(); Motion.attachment = nil end
        if Motion.humanoid and Motion.humanoid.Parent and Motion.savedAutoRotate ~= nil then
            Motion.humanoid.AutoRotate = Motion.savedAutoRotate
        end
        if Motion.root and Motion.root.Parent and Motion.mode ~= "WALK" then
            if not SafeMode.Enabled and (Motion.owner == "Farm" or Motion.owner == "Swords") and Motion.kind == "mob" then
                pcall(function()
                    local position = Motion.root.Position
                    Motion.root.CFrame = CFrame.lookAt(position, position - (Motion.direction or Vector3.new(0, 0, 1)))
                end)
            end
            Motion.root.AssemblyLinearVelocity = zero
            Motion.root.AssemblyAngularVelocity = zero
        end
        Motion.owner, Motion.target, Motion.root, Motion.humanoid = nil, nil, nil, nil
        Motion.mode, Motion.aimPoint, Motion.savedAutoRotate = nil, nil, nil
        Motion.arrived, Motion.walkRange, QuestRuntime.AimTarget = false, nil, nil
    end

    function Motion.allowed(owner)
        if ManualFlight.Enabled then return false end
        if destroyed then return false end
        if owner == "Manual" then return true end
        if QuestRuntime.SwordEnabled then
            if owner == "Farm" and not QuestRuntime.SwordBossAssist then return false end
            if owner == "Items" then return false end
            if owner == "Swords" and QuestRuntime.SwordBossAssist then return false end
        end
        if Motion.owner == "Manual" or os.clock() < Motion.manualUntil then return false end
        if autoQuestEnabled and owner ~= "Quest" then return false end
        if QuestRuntime.AcceptanceMoving and owner ~= "Quest" then return false end
        -- O deslocamento de volta ao NPC tem prioridade sobre o Auto Farm,
        -- inclusive antes do primeiro pedido de movimento da quest.
        if owner == "Farm" and QuestRuntime.QuestPriority then return false end
        -- Once a quest is accepted, remain at the NPC until the player explicitly
        -- selects a combat mob in the Auto Farm target list.
        if owner == "Farm" and QuestRuntime.WaitForFarmSelection then return false end
        if owner == "Farm" and Motion.owner and Motion.owner ~= "Farm" then return false end
        return true
    end

    function Motion.request(owner, target, spacing, kind, destination)
        if not Motion.allowed(owner) then return false end
        local character, root, humanoid = Motion.character()
        if not character or (target and (not target.Parent or not target:IsDescendantOf(workspace))) then return false end
        if target and os.clock() < (Motion.blocked[target] or 0) then return false end
        local pointChanged = (owner == "Farm" or owner == "Swords") and kind == "point" and Motion.kind == "point"
            and typeof(destination) == "Vector3" and typeof(Motion.destination) == "Vector3"
            and SafeMode.flatDistance(destination, Motion.destination) > 5
        if Motion.owner ~= owner or Motion.target ~= target or Motion.root ~= root or Motion.kind ~= kind or pointChanged then
            Motion.release()
            Motion.owner, Motion.target, Motion.root, Motion.humanoid = owner, target, root, humanoid
            Motion.kind, Motion.mode, Motion.arrived = kind, "APPROACH", false
            Motion.direction, Motion.startedAt, Motion.lastProgressAt = nil, os.clock(), os.clock()
            Motion.bestDistance, Motion.lastTeleportAt, Motion.teleportAttempts = math.huge, -math.huge, 0
            Motion.streamToken = (Motion.streamToken or 0) + 1
            Motion.streamPending, Motion.streamReady, Motion.streamPosition = false, not workspace.StreamingEnabled, nil
        end
        Motion.spacing, Motion.destination, Motion.lease = spacing or 0, destination, os.clock() + 1.5
        return true
    end

    -- Preserve original instantaneous repositioning for short jumps and guarded callers.
    function Motion.pivotDirect(character, root, destination, islandPoint)
        if SafeMode.Enabled and (not SafeMode.isTravelPoint(islandPoint)
            or (destination.Position - islandPoint.position).Magnitude > 0.05) then return false end
        if not character or not character.Parent or not root or not root.Parent then return false end
        local origin = root.Position
        destination = Landing.destination(character, root, destination)
        local ok = pcall(function() character:PivotTo(destination) end)
        if not ok or (root.Position - destination.Position).Magnitude > 0.05 then
            local moved = pcall(function() root.CFrame = destination end)
            if not moved then return false end
        end
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = zero, zero
        local arrived = (root.Position - destination.Position).Magnitude <= 1
        if arrived then Landing.watch(character, root, destination, origin) end
        return arrived, destination
    end

    -- Motion.pivot is used by Auto Farm, Auto Quest and Auto Chest.
    -- A long jump is deferred and preloaded; heartbeat callers never yield.
    function Motion.pivot(character, root, destination)
        if SafeMode.Enabled then return false end
        if destroyed or typeof(destination) ~= "CFrame" or not root or not root.Parent then return false end
        local previous = Motion.longTravel
        if previous and not previous.cancelled then
            -- Repeated farm updates for the same target should not restart the animation.
            if previous.root == root and (previous.destination.Position - destination.Position).Magnitude < 160 then
                return false
            end
            Motion.cancelLongTravel()
        end
        if not TeleportLoading.isLong(root, destination.Position) then
            return Motion.pivotDirect(character, root, destination)
        end

        local owner = Motion.owner or "Items"
        local selectedTarget = Motion.target
        local job = {owner = owner, target = selectedTarget, root = root,
            destination = destination, cancelled = false}
        Motion.longTravel = job
        local title = owner == "Quest" and "TRAVELING TO QUEST"
            or owner == "Items" and "TRAVELING TO CHEST"
            or owner == "Farm" and "TRAVELING TO TARGET"
            or "LOADING DESTINATION"
        local ticket = TeleportLoading.begin("auto:" .. owner, title)
        job.ticket = ticket
        task.spawn(function()
            local function valid()
                if destroyed or job.cancelled or Motion.longTravel ~= job
                    or not character.Parent or not root.Parent then return false end
                if owner == "Items" then return autoChestEnabled == true end
                return Motion.owner == owner and Motion.target == selectedTarget
            end
            if ticket then TeleportLoading.preload(ticket, destination.Position) end
            task.wait(0.5)
            if not valid() then
                if Motion.longTravel == job then Motion.longTravel = nil end
                if ticket then TeleportLoading.finish(ticket) end
                return
            end
            Motion.pivotDirect(character, root, destination)
            if ticket then
                if valid() then TeleportLoading.fadeOut(ticket)
                else TeleportLoading.finish(ticket) end
            end
            if Motion.longTravel == job then Motion.longTravel = nil end
        end)
        return false
    end

    function Motion.prepareStream(position)
        if not workspace.StreamingEnabled or type(LocalPlayer.RequestStreamAroundAsync) ~= "function" then
            Motion.streamReady, Motion.streamPending = true, false
            Motion.streamPosition = position
            return true
        end
        if Motion.streamPending then
            if Motion.streamPosition and (position - Motion.streamPosition).Magnitude <= 180 then return false end
            Motion.streamToken = (Motion.streamToken or 0) + 1
            if Motion.streamThread then pcall(task.cancel, Motion.streamThread); Motion.streamThread = nil end
            if Motion.streamRequestThread then pcall(task.cancel, Motion.streamRequestThread); Motion.streamRequestThread = nil end
            Motion.streamPending = false
        end
        if Motion.streamReady and Motion.streamPosition and (position - Motion.streamPosition).Magnitude <= 180 then
            return true
        end
        Motion.streamToken = (Motion.streamToken or 0) + 1
        local token = Motion.streamToken
        Motion.streamPosition, Motion.streamPending, Motion.streamReady = position, true, false
        Motion.streamStartedAt = os.clock()
        Motion.streamThread = task.spawn(function()
            local completed = false
            Motion.streamRequestThread = task.spawn(function()
                pcall(function() LocalPlayer:RequestStreamAroundAsync(position, 1.5) end)
                completed = true
                if Motion.streamToken == token then Motion.streamRequestThread = nil end
            end)
            local started = os.clock()
            while not completed and os.clock() - started < 0.65 do
                if destroyed or Motion.streamToken ~= token then return end
                task.wait(0.05)
            end
            if destroyed or Motion.streamToken ~= token then return end
            -- Streaming is a best-effort preload, not a prerequisite that can freeze TP.
            Motion.streamPending, Motion.streamReady = false, true
            if Motion.streamRequestThread then pcall(task.cancel, Motion.streamRequestThread); Motion.streamRequestThread = nil end
            Motion.streamThread = nil
        end)
        return false
    end

    function Motion.cancelManual()
        Motion.manualGeneration = (Motion.manualGeneration or 0) + 1
        if Motion.manualThread then pcall(task.cancel, Motion.manualThread); Motion.manualThread = nil end
        if Motion.manualStreamThread then pcall(task.cancel, Motion.manualStreamThread); Motion.manualStreamThread = nil end
        TeleportLoading.cancelOwner("island")
    end

    function Motion.travelIsland(point, valid, owner)
        if not SafeMode.isTravelPoint(point) or not valid() then return false end
        local character, root, humanoid = Motion.character()
        if not character then return false end
        local destination = CFrame.new(point.position)
        local ticket = TeleportLoading.isLong(root, point.position)
            and TeleportLoading.begin(owner or "island", "TRAVELING TO ISLAND") or nil
        if ticket then TeleportLoading.preload(ticket, point.position); task.wait(0.5) end
        local function active()
            local currentCharacter, currentRoot = Motion.character()
            return not destroyed and valid() and currentCharacter == character and currentRoot == root
        end
        if not active() then if ticket then TeleportLoading.finish(ticket) end; return false end
        local moved, landing = Motion.pivotDirect(character, root, destination, point)
        if not SafeMode.Enabled then humanoid:Move(zero, false); humanoid:MoveTo(root.Position) end
        if ticket then TeleportLoading.fadeOut(ticket) end
        task.wait(0.35)
        if not active() then if ticket then TeleportLoading.finish(ticket) end; return false end
        if SafeMode.flatDistance(root.Position, (landing or destination).Position) > 6 then
            moved, landing = Motion.pivotDirect(character, root, destination, point)
            if not SafeMode.Enabled then humanoid:Move(zero, false); humanoid:MoveTo(root.Position) end
        end
        return moved and SafeMode.flatDistance(root.Position, (landing or destination).Position) <= 6
    end

    function Motion.manual(destination)
        if destroyed or typeof(destination) ~= "CFrame" then return false end
        local point, distance = SafeMode.nearestIsland(destination.Position)
        if not point or distance > 1 or (point.position - destination.Position).Magnitude > 1 then return false end
        Motion.manualUntil = os.clock() + 5
        Motion.cancelManual()
        local token = Motion.manualGeneration
        if QuestRuntime.CancelInteraction then QuestRuntime.CancelInteraction() end
        if QuestRuntime.CancelAcceptance then QuestRuntime.CancelAcceptance("manual") end
        if QuestRuntime.StopFarmSearch then QuestRuntime.StopFarmSearch() end
        Motion.release()
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        if not Motion.character() then return false end
        local pending = true
        local worker = task.spawn(function()
            local function active() return not destroyed and token == Motion.manualGeneration end
            if SafeMode.Enabled then
                Motion.walkTo("Manual", point.position, nil, active, 3)
            else
                Motion.travelIsland(point, active, "island")
            end
            if not active() then return end
            Motion.manualUntil, Motion.manualThread, pending = os.clock() + 1.3, nil, false
        end)
        if pending then Motion.manualThread = worker end
        return true
    end

    function Motion.fly(root, humanoid)
        if SafeMode.Enabled then return end
        if Motion.velocity and Motion.velocity.Parent == root then return end
        Motion.savedAutoRotate = humanoid.AutoRotate
        humanoid.AutoRotate = false
        local attachment = Instance.new("Attachment")
        Motion.attachment = attachment
        attachment.Name, attachment.Parent = "RandomHubFlightAttachment", root
        local velocity = Instance.new("LinearVelocity")
        Motion.velocity = velocity
        velocity.Name = "RandomHubFlightVelocity"
        velocity.Attachment0 = attachment
        velocity.RelativeTo = Enum.ActuatorRelativeTo.World
        velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        velocity.ForceLimitsEnabled = false
        velocity.VectorVelocity = zero
        velocity.Parent = root
    end

    function Motion.step(dt)
        SafeMode.tickKeys()
        Landing.step()
        if not Motion.owner then return end
        local now = os.clock()
        if not Motion.allowed(Motion.owner) or now > Motion.lease then Motion.release(); return end
        local character, root, humanoid = Motion.character()
        if not character or root ~= Motion.root then Motion.release(); return end
        if Motion.longTravel and Motion.longTravel.owner == Motion.owner then return end
        local target = Motion.target
        if target and (not target.Parent or not target:IsDescendantOf(workspace)
            or (Motion.kind == "mob" and not World.liveMob(target))) then Motion.release(); return end
        local part = target and World.root(target)
        local targetPosition = part and part.Position or Motion.destination
        if not targetPosition then Motion.release(); return end
        local delta = root.Position - targetPosition
        if not Motion.direction then
            local flat = Vector3.new(delta.X, 0, delta.Z)
            Motion.direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
        end
        local farm = (Motion.owner == "Farm" or Motion.owner == "Swords") and Motion.kind == "mob"
        if farm then Motion.spacing = math.clamp(tonumber(farmDistance) or 1, 1, 10) end
        local height = Motion.kind == "mob" and (farm and 0 or 1.5) or (Motion.kind == "giver" and 0 or 1)
        local destination = targetPosition + Motion.direction * Motion.spacing + Vector3.new(0, height, 0)
        if Motion.kind == "point" then destination = targetPosition end
        if SafeMode.Enabled then
            if Motion.kind == "mob" then destination = targetPosition + Motion.direction * Motion.spacing end
            SafeMode.step(character, root, humanoid, targetPosition, destination, now)
            return
        end

        if Motion.kind == "fruit" or Motion.kind == "item" then
            if Motion.velocity then Motion.velocity:Destroy(); Motion.velocity = nil end
            if Motion.attachment then Motion.attachment:Destroy(); Motion.attachment = nil end
            if Motion.savedAutoRotate ~= nil then
                humanoid.AutoRotate = Motion.savedAutoRotate
                Motion.savedAutoRotate = nil
            end
            destination = targetPosition + Motion.direction * Motion.spacing + Vector3.new(0, 1, 0)
            local distance = (destination - root.Position).Magnitude
            Motion.arrived = distance <= 2
            if Motion.arrived then return end
            if distance > Motion.threshold and not Motion.prepareStream(targetPosition) then return end
            if now - (Motion.lastTeleportAt or -math.huge) < 0.45 then return end
            Motion.lastTeleportAt = now
            Motion.pivot(character, root, CFrame.lookAt(destination, targetPosition))
            return
        end

        if farm then
            local head = target:FindFirstChild("Head")
            local anchor = head and head:IsA("BasePart") and head or part
            local top = anchor.Position + Vector3.new(0, anchor.Size.Y * 0.5, 0)
            destination = top + Vector3.new(0, Motion.spacing, 0)
            if delta.Magnitude > 180 then Motion.prepareStream(targetPosition) end
            if Motion.savedAutoRotate == nil then Motion.savedAutoRotate = humanoid.AutoRotate end
            humanoid.AutoRotate = false
            Motion.mode = "TELEPORT"
            Motion.lastTeleportAt = now
            Motion.pivot(character, root, CFrame.lookAt(destination, top, Motion.direction))
            Motion.arrived = (destination - root.Position).Magnitude <= 0.25
            QuestRuntime.AimTarget = target
            return
        end

        -- Request the target region before moving across islands so streamed terrain and mobs
        -- have time to replicate. This runs asynchronously and never blocks Heartbeat.
        if (Motion.kind == "mob" or Motion.kind == "item" or Motion.kind == "point" or (Motion.kind == "giver" and QuestRuntime.AcceptanceMoving))
            and delta.Magnitude > Motion.threshold then
            local streamReady = Motion.prepareStream(targetPosition)
            -- A slow or unsupported stream request must not freeze the NPC teleport.
            if not streamReady and now - (Motion.streamStartedAt or now) < 3 then return end
        end

        -- The selected quest NPC uses repeated, rate-limited teleport rather
        -- than giving up after four PivotTo attempts (some servers correct position).
        if Motion.owner == "Quest" and Motion.kind == "giver" and QuestRuntime.AcceptanceMoving then
            local distance = (destination - root.Position).Magnitude
            Motion.arrived = distance <= 2
            if not Motion.arrived and now - (Motion.lastTeleportAt or -math.huge) >= 0.45 then
                Motion.lastTeleportAt = now
                Motion.lastQuestGiverTeleportAt = now
                Motion.pivot(character, root, CFrame.lookAt(destination, targetPosition))
            end
            QuestRuntime.AimTarget = nil
            return
        end

        -- Keep the existing quest-mob behavior independent from the acceptance NPC.
        if Motion.owner == "Quest" and Motion.kind == "mob" then
            local distance = (destination - root.Position).Magnitude
            Motion.arrived = distance <= 2.5
            if not Motion.arrived and now - (Motion.lastTeleportAt or -math.huge) >= 0.4 then
                Motion.lastTeleportAt = now
                Motion.pivot(character, root, CFrame.lookAt(destination, targetPosition))
            end
            QuestRuntime.AimTarget = target
            return
        end

        if Motion.mode == "APPROACH" then
            if delta.Magnitude > Motion.threshold then
                if now - Motion.lastTeleportAt < 1 then return end
                if Motion.teleportAttempts and Motion.teleportAttempts >= 2 then
                    if target then Motion.blocked[target] = now + 8 end
                    Motion.release(); return
                end
                Motion.teleportAttempts = (Motion.teleportAttempts or 0) + 1
                Motion.lastTeleportAt = now
                local staging = targetPosition + Motion.direction * 12 + Vector3.new(0, 1, 0)
                Motion.pivot(character, root, CFrame.lookAt(staging, targetPosition))
                return
            end
            Motion.mode = "FLY"
            Motion.teleportAttempts = 0
        end
        Motion.fly(root, humanoid)
        local offset = destination - root.Position
        local distance = offset.Magnitude
        Motion.arrived = distance <= 1.25
        if distance < Motion.bestDistance - 0.5 or Motion.arrived
            or (Motion.kind == "mob" and delta.Magnitude <= math.max(6, Motion.spacing + 3)) then
            Motion.bestDistance, Motion.lastProgressAt = distance, now
        elseif now - Motion.lastProgressAt > 10 then
            if target then Motion.blocked[target] = now + 8 end
            Motion.release(); return
        end
        local speed = math.min(Motion.speed, distance / math.max(dt, 1 / 60))
        Motion.velocity.VectorVelocity = distance > 0.35 and offset.Unit * speed or zero
        local facing = Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)
        if (facing - root.Position).Magnitude > 0.05 then root.CFrame = CFrame.lookAt(root.Position, facing) end
        QuestRuntime.AimTarget = Motion.owner == "Quest" and Motion.kind == "mob" and target or nil
    end

    function Motion.lockFarmView(camera, part, root)
        local saved = Motion.farmView
        if saved and saved.camera ~= camera then Motion.releaseAim(); saved = nil end
        if not saved then
            local offset = camera.CFrame.Position - root.Position
            local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
            saved = {
                camera = camera, cameraType = camera.CameraType, subject = camera.CameraSubject,
                distance = math.clamp(horizontal, 6, 24), height = math.clamp(offset.Y, 2, 12),
            }
            Motion.farmView = saved
            Motion.mouseUnavailable = false
        end
        camera.CameraType = Enum.CameraType.Scriptable
        local direction = Motion.direction or Vector3.new(0, 0, 1)
        local position = root.Position + direction * saved.distance + Vector3.new(0, saved.height, 0)
        camera.CFrame = CFrame.lookAt(position, part.Position)
        camera.Focus = CFrame.new(part.Position)
    end

    function Motion.aim()
        Motion.aimPoint = nil
        if SafeMode.Enabled then Motion.releaseAim(); return end
        local target = QuestRuntime.AimTarget
        local farm = QuestRuntime.AutoFarmEnabled == true and Motion.owner == "Farm" and Motion.kind == "mob"
        local quest = autoQuestEnabled and Motion.owner == "Quest" and Motion.kind == "mob"
        if destroyed or not (farm or quest) or not target or target ~= Motion.target
            or not Motion.allowed(Motion.owner) or os.clock() > (Motion.lease or 0)
            or not World.liveMob(target) or QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving
            or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy then
            Motion.releaseAim()
            return
        end
        local _, root = Motion.character()
        local camera, part = workspace.CurrentCamera, getMobRoot(target)
        if not camera or not part or not root or root ~= Motion.root then Motion.releaseAim(); return end
        if farm then Motion.lockFarmView(camera, part, root) else Motion.releaseAim() end
        local point, visible = camera:WorldToViewportPoint(part.Position)
        if not farm and (not visible or point.Z <= 0 or Motion.mouseUnavailable) then
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
            point, visible = camera:WorldToViewportPoint(part.Position)
        end
        if visible and point.Z > 0 then
            Motion.aimPoint = Vector2.new(point.X, point.Y)
            if not farm and not Motion.mouseUnavailable then
                local ok = pcall(function() VirtualInputManager:SendMouseMoveEvent(point.X, point.Y, game) end)
                Motion.mouseUnavailable = not ok
            end
        end
    end

    local elapsed, lastError = 0, -math.huge
    connect(RunService.Heartbeat, function(dt)
        elapsed = elapsed + dt
        local interval = SafeMode.Enabled and 0.1 or ((Motion.owner == "Farm" or Motion.owner == "Swords") and Motion.kind == "mob" and Motion.farmTeleportInterval or 1 / 30)
        if elapsed + 0.000001 < interval then return end
        local step = math.min(elapsed, 0.15)
        elapsed = elapsed % interval
        local ok, err = pcall(Motion.step, step)
        if not ok then
            Motion.release()
            if os.clock() - lastError > 8 then warn("[Random Hub | Movimento] " .. tostring(err)); lastError = os.clock() end
        end
    end)
    local aimBinding = "RandomHubFarmAim_" .. tostring(ScreenGui)
    local function updateAim()
        local ok = pcall(Motion.aim)
        if not ok then Motion.releaseAim() end
    end
    local aimBound = pcall(function()
        RunService:BindToRenderStep(aimBinding, Enum.RenderPriority.Camera.Value + 1, updateAim)
    end)
    if not aimBound then connect(RunService.RenderStepped, updateAim) end
    connect(LocalPlayer.CharacterRemoving, function()
        World.characterUnavailable = true
        if QuestRuntime.CancelAcceptance then QuestRuntime.CancelAcceptance("respawn") end
        if QuestRuntime.StopFarmSearch then QuestRuntime.StopFarmSearch() end
        Motion.cancelManual()
        Motion.release()
        if QuestRuntime.StopItems then QuestRuntime.StopItems() end
        if QuestRuntime.CancelInteraction then QuestRuntime.CancelInteraction() end
    end)
    connect(LocalPlayer.CharacterAdded, function() World.characterUnavailable = false end)
    Stoppers.Runtime = function()
        if aimBound then pcall(function() RunService:UnbindFromRenderStep(aimBinding) end) end
        Motion.release()
        Motion.cancelManual()
        if indexThread then pcall(task.cancel, indexThread) end
    end
end)


Graphics = {
    enabled = false, generation = 0,
    saved = setmetatable({}, {__mode = "k"}),
    detached = {}, queue = {}, queued = {}, head = 1,
    -- Client-side visual radius. Roblox's server-side StreamingEnabled radius
    -- cannot be reliably set from a local script.
    maxMapDistance = 450,
    distanceParts = setmetatable({}, {__mode = "k"}),
    distanceHidden = setmetatable({}, {__mode = "k"}),
}

runSection("Graphics", function()
    local Lighting = game:GetService("Lighting")

    function Graphics.visual(object)
        return object:IsA("BasePart") or object:IsA("Decal") or object:IsA("Texture")
            or object:IsA("SpecialMesh") or object:IsA("SurfaceAppearance") or object:IsA("ParticleEmitter")
            or object:IsA("Beam") or object:IsA("Trail") or object:IsA("Light")
            or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles")
            or object:IsA("PostEffect") or object:IsA("Atmosphere") or object:IsA("Highlight")
    end

    function Graphics.isMap(object, initial)
        local map, transient, anchored = false, false, false
        local node = object
        while node and node ~= workspace and node ~= game do
            if node == Lighting then return true end
            if node:IsA("Tool") or (node:IsA("Model") and node:FindFirstChildOfClass("Humanoid")) then return false end
            local name = string.lower(node.Name):gsub("[^%w]", "")
            for _, hint in ipairs({"skill", "ability", "abilities", "habilidade", "attack", "combat", "spell", "magic", "projectile", "hitbox", "damage", "slash", "aura"}) do
                if name:find(hint, 1, true) then return false end
            end
            if World.fruitName(node.Name) then return false end
            if name == "map" or name == "world" or name == "environment" or name == "terrain"
                or name == "islands" or name:find("island", 1, true) or name:find("decoration", 1, true)
                or name == "buildings" or name == "trees" or name == "foliage" or name == "scenery" then map = true end
            if name == "fx" or name == "vfx" or name == "effects" or name == "effect" then transient = true end
            if node:IsA("BasePart") and node.Anchored then anchored = true end
            node = node.Parent
        end
        if transient and not initial then return false end
        if map then return true end
        local geometry = object:IsA("BasePart") or object:IsA("Decal") or object:IsA("Texture")
            or object:IsA("SpecialMesh") or object:IsA("SurfaceAppearance")
        return initial == true and geometry and anchored and not transient
    end

    function Graphics.write(object, property, value)
        local ok, current = pcall(function() return object[property] end)
        if not ok or current == value then return false end
        local values = Graphics.saved[object]
        if not values then values = {}; Graphics.saved[object] = values end
        local previous = values[property]
        if not previous or current ~= previous.applied then previous = {original = current}; values[property] = previous end
        local changed = pcall(function() object[property] = value end)
        if changed then previous.applied = value else values[property] = nil end
        return changed
    end

    function Graphics.original(object, property)
        local values = Graphics.saved[object]
        local previous = values and values[property]
        local current = object[property]
        if previous and current == previous.applied then return previous.original end
        return current
    end

    -- Use the nearest point on the part's box, not its center. This avoids
    -- hiding giant floors/bridges that still reach inside the 450-stud radius.
    function Graphics.mapPartTooFar(part, position)
        local localPos = part.CFrame:PointToObjectSpace(position)
        local half = part.Size * 0.5
        local x = math.max(math.abs(localPos.X) - half.X, 0)
        local y = math.max(math.abs(localPos.Y) - half.Y, 0)
        local z = math.max(math.abs(localPos.Z) - half.Z, 0)
        local limit = Graphics.maxMapDistance
        return x*x + y*y + z*z > limit*limit
    end

    function Graphics.restoreMapDistance(part)
        local values = Graphics.saved[part]
        local previous = values and values.LocalTransparencyModifier
        if previous then
            pcall(function()
                -- Do not overwrite changes another script made in the meantime.
                if part.LocalTransparencyModifier == previous.applied then
                    part.LocalTransparencyModifier = previous.original
                end
            end)
            values.LocalTransparencyModifier = nil
            if next(values) == nil then Graphics.saved[part] = nil end
        end
        Graphics.distanceHidden[part] = nil
    end

    function Graphics.updateMapDistance(part, origin)
        if not part or not part.Parent or not part:IsDescendantOf(workspace) then
            Graphics.distanceParts[part] = nil
            Graphics.distanceHidden[part] = nil
            return
        end
        if Graphics.mapPartTooFar(part, origin) then
            if Graphics.write(part, "LocalTransparencyModifier", 1) then
                Graphics.distanceHidden[part] = true
            end
        elseif Graphics.distanceHidden[part] then
            Graphics.restoreMapDistance(part)
        end
    end

    function Graphics.apply(object, initial)
        if not Graphics.enabled or destroyed or not object.Parent or not Graphics.visual(object) then return end
        local map = Graphics.isMap(object, initial)
        if object:IsA("BasePart") then
            Graphics.write(object, "CastShadow", false)
            if map and object.Anchored and object:IsDescendantOf(workspace) then
                Graphics.distanceParts[object] = true
            end
            if map then
                Graphics.write(object, "Material", Enum.Material.SmoothPlastic)
                Graphics.write(object, "MaterialVariant", "")
                Graphics.write(object, "Reflectance", 0)
            end
            if object:IsA("MeshPart") then
                Graphics.write(object, "RenderFidelity", Enum.RenderFidelity.Performance)
                if map then Graphics.write(object, "TextureID", "") end
            end
        elseif object:IsA("Texture") or object:IsA("Decal") then
            if map then Graphics.write(object, "Transparency", 1) end
        elseif object:IsA("SpecialMesh") then
            if map then Graphics.write(object, "TextureId", "") end
        elseif object:IsA("SurfaceAppearance") then
            if map and not Graphics.detached[object] then
                local parent = object.Parent
                local ok = pcall(function() object.Parent = nil end)
                if ok then Graphics.detached[object] = parent end
            end
        elseif object:IsA("ParticleEmitter") then
            if map then
                Graphics.write(object, "Enabled", false)
                Graphics.write(object, "Rate", 0)
                Graphics.write(object, "Lifetime", NumberRange.new(0))
                pcall(function() object:Clear() end)
            else
                local rate, life = Graphics.original(object, "Rate"), Graphics.original(object, "Lifetime")
                Graphics.write(object, "Rate", math.min(rate * 0.25, 20))
                Graphics.write(object, "Lifetime", NumberRange.new(math.min(life.Min * 0.6, 0.6), math.min(life.Max * 0.6, 0.9)))
            end
        elseif object:IsA("Beam") or object:IsA("Trail") then
            if map then Graphics.write(object, "Enabled", false)
            elseif object:IsA("Beam") then Graphics.write(object, "Segments", math.min(Graphics.original(object, "Segments"), 2))
            else
                Graphics.write(object, "Lifetime", math.min(Graphics.original(object, "Lifetime") * 0.5, 0.3))
                Graphics.write(object, "MinLength", math.max(Graphics.original(object, "MinLength"), 0.2))
            end
        elseif object:IsA("Light") then
            Graphics.write(object, "Shadows", false)
            if map then Graphics.write(object, "Enabled", false)
            else
                Graphics.write(object, "Brightness", Graphics.original(object, "Brightness") * 0.35)
                Graphics.write(object, "Range", Graphics.original(object, "Range") * 0.6)
            end
        elseif object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles") then
            if map then Graphics.write(object, "Enabled", false)
            elseif object:IsA("Smoke") then
                Graphics.write(object, "Opacity", Graphics.original(object, "Opacity") * 0.4)
                Graphics.write(object, "Size", Graphics.original(object, "Size") * 0.6)
            elseif object:IsA("Fire") then Graphics.write(object, "Size", Graphics.original(object, "Size") * 0.6) end
        elseif object:IsA("PostEffect") then
            if map then Graphics.write(object, "Enabled", false)
            elseif object:IsA("BlurEffect") then Graphics.write(object, "Size", math.min(Graphics.original(object, "Size"), 6))
            elseif object:IsA("BloomEffect") then Graphics.write(object, "Intensity", Graphics.original(object, "Intensity") * 0.3) end
        elseif object:IsA("Atmosphere") and map then
            if not Graphics.detached[object] then
                local previousParent = object.Parent
                local ok = pcall(function() object.Parent = nil end)
                if ok then Graphics.detached[object] = previousParent end
            end
        elseif object:IsA("Highlight") and map then Graphics.write(object, "Enabled", false) end
    end

    function Graphics.restore(object)
        local values = Graphics.saved[object]
        if not values then return end
        for property, previous in pairs(values) do
            pcall(function()
                if object[property] == previous.applied then object[property] = previous.original end
            end)
        end
        Graphics.saved[object] = nil
    end

    function Graphics.restoreDetached()
        for object, parent in pairs(Graphics.detached) do
            pcall(function()
                if object.Parent == nil then
                    if parent.Parent then object.Parent = parent else object:Destroy() end
                end
            end)
            Graphics.detached[object] = nil
        end
    end

    function Graphics.enqueue(object)
        if not Graphics.enabled or destroyed or Graphics.queued[object] or not Graphics.visual(object) then return end
        Graphics.queued[object] = true
        Graphics.queue[#Graphics.queue + 1] = object
    end

    function Graphics.stopWorker()
        if Graphics.worker then pcall(task.cancel, Graphics.worker); Graphics.worker = nil end
        if Graphics.distanceWorker then pcall(task.cancel, Graphics.distanceWorker); Graphics.distanceWorker = nil end
        if Graphics.lightingConnection then Graphics.lightingConnection:Disconnect(); Graphics.lightingConnection = nil end
        World.onVisualAdded = nil
        Graphics.queue, Graphics.queued, Graphics.head = {}, {}, 1
        Graphics.distanceParts = setmetatable({}, {__mode = "k"})
        Graphics.distanceHidden = setmetatable({}, {__mode = "k"})
    end

    function Graphics.startDistanceWorker(token)
        Graphics.distanceWorker = task.spawn(function()
            local lastPosition, lastPass = nil, -math.huge
            while Graphics.enabled and token == Graphics.generation and not destroyed do
                local character = LocalPlayer.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                local origin = root and root.Position
                local now = os.clock()
                if origin and (not lastPosition or (origin - lastPosition).Magnitude >= 20 or now - lastPass >= 1.5) then
                    lastPosition, lastPass = origin, now
                    local processed = 0
                    for part in pairs(Graphics.distanceParts) do
                        if not Graphics.enabled or token ~= Graphics.generation or destroyed then return end
                        pcall(Graphics.updateMapDistance, part, origin)
                        processed = processed + 1
                        if processed % 200 == 0 then task.wait() end
                    end
                end
                task.wait(0.25)
            end
        end)
    end

    function Graphics.setEnabled(state)
        -- Preserve the original lighting baseline when FPS Boost changes state.
        if TeleportLoading.current then TeleportLoading.finish() end
        Graphics.generation = Graphics.generation + 1
        local token = Graphics.generation
        Graphics.enabled = state == true and not destroyed
        Graphics.stopWorker()
        if not Graphics.enabled then
            Graphics.worker = task.spawn(function()
                local count = 0
                for object in pairs(Graphics.saved) do
                    if token ~= Graphics.generation then return end
                    Graphics.restore(object)
                    count = count + 1
                    if count % 150 == 0 then task.wait() end
                end
                if token == Graphics.generation then Graphics.restoreDetached() end
            end)
            return
        end
        World.onVisualAdded = Graphics.enqueue
        Graphics.lightingConnection = Lighting.DescendantAdded:Connect(Graphics.enqueue)
        Graphics.startDistanceWorker(token)
        Graphics.worker = task.spawn(function()
            -- Fog makes the horizon fade out by 450 studs (Terrain included).
            -- Together with locally hidden distant map parts this gives a
            -- visual draw-distance limit without editing the server map.
            Graphics.write(Lighting, "FogStart", 320)
            Graphics.write(Lighting, "FogEnd", Graphics.maxMapDistance)
            Graphics.write(Lighting, "GlobalShadows", false)
            Graphics.write(Lighting, "EnvironmentDiffuseScale", 0)
            Graphics.write(Lighting, "EnvironmentSpecularScale", 0)
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                Graphics.write(terrain, "Decoration", false)
                Graphics.write(terrain, "WaterWaveSize", 0)
                Graphics.write(terrain, "WaterWaveSpeed", 0)
                Graphics.write(terrain, "WaterReflectance", 0)
            end
            for _, scope in ipairs({workspace, Lighting}) do
                for index, object in ipairs(scope:GetDescendants()) do
                    if not Graphics.enabled or token ~= Graphics.generation or destroyed then return end
                    pcall(Graphics.apply, object, true)
                    if index % 150 == 0 then task.wait() end
                end
            end
            while Graphics.enabled and token == Graphics.generation and not destroyed do
                local count = 0
                while Graphics.head <= #Graphics.queue and count < 100 do
                    local object = Graphics.queue[Graphics.head]
                    Graphics.queue[Graphics.head] = false
                    Graphics.head = Graphics.head + 1
                    Graphics.queued[object] = nil
                    pcall(Graphics.apply, object, false)
                    count = count + 1
                end
                if Graphics.head > #Graphics.queue then Graphics.queue, Graphics.head = {}, 1 end
                task.wait(0.15)
            end
        end)
    end

    Stoppers.Graphics = function()
        Graphics.enabled = false
        Graphics.generation = Graphics.generation + 1
        Graphics.stopWorker()
        for object in pairs(Graphics.saved) do Graphics.restore(object) end
        Graphics.restoreDetached()
    end
end)

runSection("Combat", function()
    local CombatPage = Pages.Combat

    local CombatCfg = {
        AutoAttackEnabled = false,
        AttackDelay = 0.2,
        ClickVIM = true,
        ClickVirtualUser = true,
        AutoEquipEnabled = false,
        SelectedSlot = nil,
        LastEquippedTool = nil,
        EquipThread = nil,
        EquipToken = 0,
        EquipCharacter = LocalPlayer.Character,
        SelectedToolName = nil,
        NextSlotInputAt = 0,
        EquipInputKey = nil,
        EquipLastErrorAt = -math.huge,
        EquipRespawnDelay = 2.5,
        EquipRespawnReadyAt = 0,
        EquipAwaitingRespawn = false,
        AutoSkillEnabled = false,
        SkillInterval = 1,
        SkillKeyGap = 0.12,
        SelectedSkills = {},
        SkillThread = nil,
        SkillBusy = false,
    }

    local SKILL_KEYS = {
        {Key = "Z", Label = "Z", Code = Enum.KeyCode.Z},
        {Key = "X", Label = "X", Code = Enum.KeyCode.X},
        {Key = "C", Label = "C", Code = Enum.KeyCode.C},
        {Key = "V", Label = "V", Code = Enum.KeyCode.V},
        {Key = "G", Label = "G", Code = Enum.KeyCode.G},
    }

    local function combatPressKey(keyCode)
        local pressed = pcall(function()
            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        end)
        if pressed then task.wait(0.05) end
        local released = pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
        return pressed and released
    end

    local SLOT_KEYS = {
        [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two, [3] = Enum.KeyCode.Three,
        [4] = Enum.KeyCode.Four, [5] = Enum.KeyCode.Five, [6] = Enum.KeyCode.Six,
        [7] = Enum.KeyCode.Seven, [8] = Enum.KeyCode.Eight, [9] = Enum.KeyCode.Nine,
        [10] = Enum.KeyCode.Zero,
    }

    local function combatPressSlotKey(slot)
        local keyCode = SLOT_KEYS[slot]
        if keyCode then return combatPressKey(keyCode) end
        return false
    end

    local function combatCancelThread(thread)
        if thread then pcall(task.cancel, thread) end
    end

    local function combatStopEquipLoop()
        CombatCfg.EquipToken = CombatCfg.EquipToken + 1
        local previous = CombatCfg.EquipThread
        CombatCfg.EquipThread = nil
        combatCancelThread(previous)
        local key = CombatCfg.EquipInputKey
        CombatCfg.EquipInputKey = nil
        if key then pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end) end
    end

    local function combatEquipIsActive(slot, token)
        return not destroyed and CombatCfg.AutoEquipEnabled
            and CombatCfg.SelectedSlot == slot and CombatCfg.EquipToken == token
    end

    local function combatToolSlot(tool)
        for _, field in ipairs({"HotbarSlot", "HotbarIndex", "SlotIndex", "Slot"}) do
            local value = tonumber(tool:GetAttribute(field))
            if not value then
                local entry = tool:FindFirstChild(field)
                if entry and entry:IsA("ValueBase") then value = tonumber(entry.Value) end
            end
            if value == 0 then value = 10 end
            if value and SLOT_KEYS[value] then return value end
        end
    end

    local function combatFindEquipTool(character, backpack, slot)
        local remembered
        for _, container in ipairs({character, backpack}) do
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local toolSlot = combatToolSlot(tool)
                    if toolSlot == slot then return tool end
                    if not toolSlot and CombatCfg.SelectedToolName and tool.Name == CombatCfg.SelectedToolName then
                        remembered = remembered or tool
                    end
                end
            end
        end
        return remembered
    end

    local function combatReleaseEquipInput()
        local key = CombatCfg.EquipInputKey
        CombatCfg.EquipInputKey = nil
        if key then pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end) end
    end

    local function combatEquipTick(slot, token)
        if not combatEquipIsActive(slot, token) then return end
        local character = LocalPlayer.Character
        if not character or not character.Parent then return end
        if CombatCfg.EquipCharacter ~= character then
            combatReleaseEquipInput()
            CombatCfg.EquipCharacter, CombatCfg.LastEquippedTool = character, nil
            CombatCfg.EquipRespawnReadyAt = os.clock() + CombatCfg.EquipRespawnDelay
            CombatCfg.EquipAwaitingRespawn = false
            CombatCfg.NextSlotInputAt, CombatCfg.NextEquipAt = CombatCfg.EquipRespawnReadyAt, 0
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        if humanoid.Health <= 0 then
            CombatCfg.EquipAwaitingRespawn, CombatCfg.EquipRespawnReadyAt = true, math.huge
            CombatCfg.LastEquippedTool = nil
            combatReleaseEquipInput()
            return
        end
        if os.clock() < CombatCfg.EquipRespawnReadyAt or QuestRuntime.AcceptanceMoving then return end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local target = combatFindEquipTool(character, backpack, slot)
        if target then
            if target.Parent ~= character and os.clock() >= (CombatCfg.NextEquipAt or 0) then
                CombatCfg.NextEquipAt = os.clock() + 0.5
                pcall(function() humanoid:EquipTool(target) end)
            end
            if target.Parent == character then
                CombatCfg.SelectedToolName, CombatCfg.LastEquippedTool = target.Name, target
                return
            end
        end
        CombatCfg.LastEquippedTool = nil
        if not backpack or os.clock() < CombatCfg.NextSlotInputAt or UserInputService:GetFocusedTextBox() then return end
        local before = character:FindFirstChildOfClass("Tool")
        CombatCfg.NextSlotInputAt = os.clock() + 1
        CombatCfg.EquipInputKey = SLOT_KEYS[slot]
        local sent = combatPressSlotKey(slot)
        combatReleaseEquipInput()
        if not sent then return end
        task.wait(0.2)
        if not combatEquipIsActive(slot, token) or LocalPlayer.Character ~= character
            or os.clock() < CombatCfg.EquipRespawnReadyAt
            or not character.Parent or humanoid.Health <= 0 then return end
        local equipped = character:FindFirstChildOfClass("Tool")
        if equipped then
            local actualSlot = combatToolSlot(equipped)
            if actualSlot == slot or (not actualSlot and (equipped ~= before or equipped.Name == CombatCfg.SelectedToolName)) then
                CombatCfg.SelectedToolName, CombatCfg.LastEquippedTool = equipped.Name, equipped
            end
        end
    end

    local function combatStartEquipLoop(slot)
        combatStopEquipLoop()
        if not CombatCfg.AutoEquipEnabled or CombatCfg.SelectedSlot ~= slot or destroyed then return end
        local token = CombatCfg.EquipToken
        local threadHandle
        threadHandle = task.spawn(function()
            while combatEquipIsActive(slot, token) do
                local ok, err = pcall(combatEquipTick, slot, token)
                if not ok and os.clock() - CombatCfg.EquipLastErrorAt >= 5 then
                    CombatCfg.EquipLastErrorAt = os.clock()
                    warn("[Random Hub | Auto Equip] " .. tostring(err))
                end
                task.wait(0.25)
            end
            if CombatCfg.EquipToken == token and CombatCfg.EquipThread == threadHandle then CombatCfg.EquipThread = nil end
        end)
        CombatCfg.EquipThread = threadHandle
    end

    local function combatSetAutoEquip(state)
        CombatCfg.AutoEquipEnabled = state == true
        local slot = CombatCfg.SelectedSlot
        if CombatCfg.AutoEquipEnabled and slot then combatStartEquipLoop(slot)
        else combatStopEquipLoop() end
    end

    local function combatSelectSlot(slot)
        combatStopEquipLoop()
        CombatCfg.LastEquippedTool, CombatCfg.SelectedToolName = nil, nil
        if not SLOT_KEYS[slot] or CombatCfg.SelectedSlot == slot then
            CombatCfg.SelectedSlot = nil
            return nil
        end
        CombatCfg.SelectedSlot = slot
        CombatCfg.NextSlotInputAt, CombatCfg.NextEquipAt = 0, 0
        if CombatCfg.AutoEquipEnabled then combatStartEquipLoop(slot) end
        return slot
    end

    local function combatMarkDead(character)
        if destroyed or not character or CombatCfg.EquipCharacter ~= character then return end
        CombatCfg.EquipAwaitingRespawn = true
        CombatCfg.EquipRespawnReadyAt = math.huge
        CombatCfg.LastEquippedTool = nil
        combatReleaseEquipInput()
    end

    local function combatStopCharacterWatch()
        CombatCfg.DeathWatchToken = (CombatCfg.DeathWatchToken or 0) + 1
        if CombatCfg.DeathWatchThread then pcall(task.cancel, CombatCfg.DeathWatchThread); CombatCfg.DeathWatchThread = nil end
        if CombatCfg.DeathConnection then CombatCfg.DeathConnection:Disconnect(); CombatCfg.DeathConnection = nil end
    end

    local function combatWatchCharacterDeath(character)
        combatStopCharacterWatch()
        if not character or destroyed then return end
        local token = CombatCfg.DeathWatchToken
        CombatCfg.DeathWatchThread = task.spawn(function()
            local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
            if destroyed or token ~= CombatCfg.DeathWatchToken or LocalPlayer.Character ~= character or not humanoid then return end
            CombatCfg.DeathWatchThread = nil
            CombatCfg.DeathConnection = humanoid.Died:Connect(function()
                if not destroyed and LocalPlayer.Character == character then combatMarkDead(character) end
            end)
            if humanoid.Health <= 0 then combatMarkDead(character) end
        end)
    end

    connect(LocalPlayer.CharacterRemoving, function(character)
        if destroyed or CombatCfg.EquipCharacter ~= character
            or (LocalPlayer.Character and LocalPlayer.Character ~= character) then return end
        combatStopCharacterWatch()
        combatMarkDead(character)
    end)
    connect(LocalPlayer.CharacterAdded, function(character)
        if destroyed or LocalPlayer.Character ~= character then return end
        if CombatCfg.EquipCharacter ~= character or CombatCfg.EquipAwaitingRespawn then
            CombatCfg.EquipCharacter, CombatCfg.LastEquippedTool = character, nil
            CombatCfg.EquipRespawnReadyAt = os.clock() + CombatCfg.EquipRespawnDelay
            CombatCfg.EquipAwaitingRespawn = false
            CombatCfg.NextSlotInputAt, CombatCfg.NextEquipAt = CombatCfg.EquipRespawnReadyAt, 0
        end
        combatWatchCharacterDeath(character)
        if CombatCfg.AutoEquipEnabled and CombatCfg.SelectedSlot and not CombatCfg.EquipThread then
            combatStartEquipLoop(CombatCfg.SelectedSlot)
        end
    end)
    combatWatchCharacterDeath(LocalPlayer.Character)

    local function combatGetClickPosition()
        local cam = workspace.CurrentCamera
        local viewport = cam and cam.ViewportSize or Vector2.new(800, 600)
        local candidates = {
            Vector2.new(viewport.X * 0.50, viewport.Y * 0.50),
            Vector2.new(viewport.X * 0.50, viewport.Y * 0.25),
            Vector2.new(viewport.X * 0.80, viewport.Y * 0.50),
            Vector2.new(viewport.X * 0.20, viewport.Y * 0.50),
            Vector2.new(viewport.X * 0.97, viewport.Y * 0.50),
            Vector2.new(viewport.X * 0.03, viewport.Y * 0.50),
        }
        if not (ScreenGui and Main and ScreenGui.Enabled) then return candidates[1] end
        local padding = 12
        local pos, size = Main.AbsolutePosition, Main.AbsoluteSize
        for _, candidate in ipairs(candidates) do
            local inside = candidate.X >= pos.X - padding and candidate.X <= pos.X + size.X + padding
                and candidate.Y >= pos.Y - padding and candidate.Y <= pos.Y + size.Y + padding
            if not inside then return candidate end
        end
        return nil
    end

    local lastAutoAttackClickPosition = nil
    local function combatReleaseAutoAttackInputs()
        local position = lastAutoAttackClickPosition
        if not position then return end
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
        end)
        pcall(function()
            local cam = workspace.CurrentCamera
            VirtualUser:Button1Up(position, cam and cam.CFrame or CFrame.new())
        end)
        lastAutoAttackClickPosition = nil
    end
    QuestRuntime.ReleaseAttack = combatReleaseAutoAttackInputs

    -- screenPunch=true envia cliques virtuais na area livre da tela, sem exigir mobs proximos.
    -- O Anti-AFK continua usando a posicao de clique anterior quando nao passa este argumento.
    combatAutoAttackClickOffscreen = function(screenPunch)
        local cam = workspace.CurrentCamera
        local viewport = cam and cam.ViewportSize or Vector2.new(800, 600)
        local candidates = {
            Vector2.new(viewport.X * 0.50, viewport.Y * 0.08),
            Vector2.new(viewport.X * 0.50, viewport.Y * 0.12),
            Vector2.new(viewport.X * 0.35, viewport.Y * 0.10),
            Vector2.new(viewport.X * 0.65, viewport.Y * 0.10),
        }
        local position
        for _, candidate in ipairs(candidates) do
            local covered = false
            if ScreenGui and Main and ScreenGui.Enabled then
                local pos, size = Main.AbsolutePosition, Main.AbsoluteSize
                covered = candidate.X >= pos.X - 8 and candidate.X <= pos.X + size.X + 8
                    and candidate.Y >= pos.Y - 8 and candidate.Y <= pos.Y + size.Y + 8
            end
            if not covered then
                position = candidate
                break
            end
        end
        if screenPunch then
            position = combatGetClickPosition()
        elseif not position then
            position = combatGetClickPosition()
        end
        if not position then return false end

        if autoQuestEnabled and not screenPunch then
            position = Motion.aimPoint
            if not position or not QuestRuntime.AimTarget or not World.liveMob(QuestRuntime.AimTarget) then return false end
            if ScreenGui.Enabled then
                local p, size = Main.AbsolutePosition, Main.AbsoluteSize
                if position.X >= p.X and position.X <= p.X + size.X and position.Y >= p.Y and position.Y <= p.Y + size.Y then return false end
            end
        end
        lastAutoAttackClickPosition = position
        local clicked = false
        if CombatCfg.ClickVIM then
            local downOK = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 0)
            end)
            task.wait(0.025)
            local upOK = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
            end)
            if downOK and upOK then
                clicked = true
            else
                pcall(function() VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0) end)
            end
        end
        if not clicked and CombatCfg.ClickVirtualUser then
            local cf = cam and cam.CFrame or CFrame.new()
            local downOK = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:Button1Down(position, cf)
            end)
            task.wait(0.025)
            local upOK = pcall(function() VirtualUser:Button1Up(position, cf) end)
            if downOK and upOK then clicked = true end
            if not clicked then pcall(function() VirtualUser:Button1Up(position, cf) end) end
        end
        pcall(function() VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0) end)
        if not clicked then pcall(function() VirtualUser:Button1Up(position, cam and cam.CFrame or CFrame.new()) end) end
        lastAutoAttackClickPosition = nil
        return clicked
    end

    -- Auto Attack somente quando houver um mob valido a ate 10 studs.
    -- A lista World.humanoids ja e atualizada por eventos; evita vasculhar o mapa todo.
    local ATTACK_MOB_RANGE = 10
    local attackNearbyMob = nil
    local attackNextScanAt = 0

    local function combatHasNearbyMob(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            attackNearbyMob = nil
            return false
        end
        local origin = root.Position
        local function isCloseMob(model)
            if not model or not World.liveMob(model) then return false end
            local mobRoot = getMobRoot(model)
            if not mobRoot then return false end
            local delta = mobRoot.Position - origin
            return math.abs(delta.X) <= ATTACK_MOB_RANGE
                and math.abs(delta.Y) <= ATTACK_MOB_RANGE
                and math.abs(delta.Z) <= ATTACK_MOB_RANGE
                and delta:Dot(delta) <= ATTACK_MOB_RANGE * ATTACK_MOB_RANGE
                and (isValidFarmMob(model) or (World.confirmCombatTarget and World.confirmCombatTarget(model)))
        end

        if isCloseMob(attackNearbyMob) then return true end
        attackNearbyMob = nil
        local now = os.clock()
        if now < attackNextScanAt then return false end
        attackNextScanAt = now + 0.25
        for humanoid in pairs(World.humanoids) do
            if humanoid.Parent and humanoid.Health > 0 then
                local model = humanoid.Parent
                if model ~= character and isCloseMob(model) then
                    attackNearbyMob = model
                    return true
                end
            end
        end
        return false
    end

    local attackThread = nil
    local attackToken = 0
    local function combatToggleAutoAttack(state)
        CombatCfg.AutoAttackEnabled = state == true
        attackToken = attackToken + 1
        local token = attackToken
        if not CombatCfg.AutoAttackEnabled then
            combatCancelThread(attackThread)
            attackThread = nil
            combatReleaseAutoAttackInputs()
            attackNearbyMob = nil
            return
        end
        combatCancelThread(attackThread)
        attackThread = nil
        combatReleaseAutoAttackInputs()
        local threadHandle
        threadHandle = task.spawn(function()
            while CombatCfg.AutoAttackEnabled and attackToken == token and not destroyed do
                -- Aciona o ataque basico apenas a 10 studs ou menos de um mob valido.
                if QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy or CombatCfg.SkillBusy then
                    combatReleaseAutoAttackInputs()
                    task.wait(0.15)
                else
                    local character = LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health <= 0 then
                        attackNearbyMob = nil
                        combatReleaseAutoAttackInputs()
                        task.wait(0.25)
                    elseif not combatHasNearbyMob(character) then
                        combatReleaseAutoAttackInputs()
                        task.wait(0.1)
                    else
                        local startedAt = os.clock()
                        local ok, clicked = pcall(combatAutoAttackClickOffscreen, true)
                        if not ok or not clicked then combatReleaseAutoAttackInputs() end
                        task.wait(math.max(0.01, CombatCfg.AttackDelay - (os.clock() - startedAt)))
                    end
                end
            end
            combatReleaseAutoAttackInputs()
            if attackThread == threadHandle then attackThread = nil end
        end)
        attackThread = threadHandle
    end

    local function combatEnsureSkillThread()
        if CombatCfg.SkillThread then return end
        local threadHandle
        threadHandle = task.spawn(function()
            while CombatCfg.AutoSkillEnabled and not destroyed do
                local cycleStartedAt = os.clock()
                for _, data in ipairs(SKILL_KEYS) do
                    if not CombatCfg.AutoSkillEnabled or destroyed then break end
                    if CombatCfg.SelectedSkills[data.Key] and not QuestRuntime.Interacting and not QuestRuntime.AcceptanceMoving and not QuestRuntime.FruitBuying and not QuestRuntime.ItemBusy
                        and (not autoQuestEnabled or QuestRuntime.Farming) then
                        CombatCfg.SkillBusy = true
                        QuestRuntime.SkillBusy = true
                        combatPressKey(data.Code)
                        task.wait(CombatCfg.SkillKeyGap)
                    end
                end
                CombatCfg.SkillBusy = false
                QuestRuntime.SkillBusy = false
                local remaining = CombatCfg.SkillInterval - (os.clock() - cycleStartedAt)
                if remaining > 0 then task.wait(remaining) end
            end
            CombatCfg.SkillBusy = false
            QuestRuntime.SkillBusy = false
            if CombatCfg.SkillThread == threadHandle then CombatCfg.SkillThread = nil end
            if CombatCfg.AutoSkillEnabled and not destroyed then combatEnsureSkillThread() end
        end)
        CombatCfg.SkillThread = threadHandle
    end

    local function combatToggleAutoSkill(state)
        CombatCfg.AutoSkillEnabled = state == true
        if not CombatCfg.AutoSkillEnabled then
            combatCancelThread(CombatCfg.SkillThread)
            CombatCfg.SkillThread = nil
            CombatCfg.SkillBusy = false
            QuestRuntime.SkillBusy = false
            for _, data in ipairs(SKILL_KEYS) do pcall(function() VirtualInputManager:SendKeyEvent(false, data.Code, false, game) end) end
            return
        end
        combatEnsureSkillThread()
    end

    stopCombat = function()
        CombatCfg.AutoAttackEnabled = false
        CombatCfg.AutoSkillEnabled = false
        CombatCfg.AutoEquipEnabled = false
        CombatCfg.SkillBusy = false
        QuestRuntime.SkillBusy = false
        attackToken = attackToken + 1
        combatCancelThread(attackThread)
        combatCancelThread(CombatCfg.SkillThread)
        combatStopEquipLoop()
        combatStopCharacterWatch()
        attackThread = nil
        CombatCfg.SkillThread = nil
        CombatCfg.EquipThread = nil
        combatReleaseAutoAttackInputs()
        for _, data in ipairs(SKILL_KEYS) do
            pcall(function() VirtualInputManager:SendKeyEvent(false, data.Code, false, game) end)
        end
        for _, keyCode in pairs({Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
            Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero}) do
            pcall(function() VirtualInputManager:SendKeyEvent(false, keyCode, false, game) end)
        end
    end

    local CombatEquipCard = createStyledCard(CombatPage, "CombatEquipCard", 110, 1)
    local CombatEquipTitle = Instance.new("TextLabel")
    CombatEquipTitle.Size = UDim2.new(1, -110, 0, 24)
    CombatEquipTitle.Position = UDim2.fromOffset(16, 9)
    CombatEquipTitle.BackgroundTransparency = 1
    CombatEquipTitle.Text = "Auto Equip"
    CombatEquipTitle.TextColor3 = Theme.Text
    CombatEquipTitle.Font = Enum.Font.GothamBold
    CombatEquipTitle.TextSize = 14
    CombatEquipTitle.TextXAlignment = Enum.TextXAlignment.Left
    CombatEquipTitle.Parent = CombatEquipCard

    local CombatEquipToggle = Instance.new("TextButton")
    CombatEquipToggle.Name = "AutoEquipToggle"
    CombatEquipToggle.Size = UDim2.fromOffset(52, 28)
    CombatEquipToggle.Position = UDim2.new(1, -68, 0, 7)
    CombatEquipToggle.BackgroundColor3 = Color3.new(1, 1, 1)
    CombatEquipToggle.BorderSizePixel = 0
    CombatEquipToggle.Text = ""
    CombatEquipToggle.AutoButtonColor = false
    CombatEquipToggle.ZIndex = 4
    CombatEquipToggle.Parent = CombatEquipCard
    addCorner(CombatEquipToggle, 14)
    local CombatEquipToggleStroke = addStroke(CombatEquipToggle, Theme.Stroke, 1, 0.3)
    local CombatEquipToggleGradient = Instance.new("UIGradient")
    CombatEquipToggleGradient.Color = TOGGLE_OFF
    CombatEquipToggleGradient.Parent = CombatEquipToggle
    local CombatEquipKnob = Instance.new("Frame")
    CombatEquipKnob.Size = UDim2.fromOffset(22, 22)
    CombatEquipKnob.Position = UDim2.new(0, 3, 0.5, -11)
    CombatEquipKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    CombatEquipKnob.BorderSizePixel = 0
    CombatEquipKnob.ZIndex = 5
    CombatEquipKnob.Parent = CombatEquipToggle
    addCorner(CombatEquipKnob, 11)
    local combatEquipEnabled = false
    local function setCombatEquipState(state)
        combatEquipEnabled = state == true
        CombatEquipToggleGradient.Color = combatEquipEnabled and TOGGLE_ON or TOGGLE_OFF
        CombatEquipToggleStroke.Transparency = combatEquipEnabled and 0.6 or 0.3
        tween(CombatEquipKnob, {Position = combatEquipEnabled and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11)}, 0.18)
        combatSetAutoEquip(combatEquipEnabled)
    end
    connect(CombatEquipToggle.MouseButton1Click, function() setCombatEquipState(not combatEquipEnabled) end)

    local CombatSlotsFrame = Instance.new("Frame")
    CombatSlotsFrame.Name = "HotbarSlots"
    CombatSlotsFrame.Size = UDim2.new(1, -32, 0, 40)
    CombatSlotsFrame.Position = UDim2.fromOffset(16, 47)
    CombatSlotsFrame.BackgroundTransparency = 1
    CombatSlotsFrame.Parent = CombatEquipCard
    local CombatSlotsLayout = Instance.new("UIListLayout")
    CombatSlotsLayout.FillDirection = Enum.FillDirection.Horizontal
    CombatSlotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CombatSlotsLayout.Padding = UDim.new(0, 5)
    CombatSlotsLayout.Parent = CombatSlotsFrame
    local combatSlotButtons = {}
    for i, slotNumber in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}) do
        local label = slotNumber == 10 and "0" or tostring(slotNumber)
        local button = Instance.new("TextButton")
        button.Name = "Slot" .. label
        button.Size = UDim2.new(0, 27, 1, 0)
        button.BackgroundColor3 = Theme.BgSecondary
        button.BorderSizePixel = 0
        button.Text = label
        button.TextColor3 = Theme.TextDim
        button.Font = Enum.Font.GothamBold
        button.TextSize = 13
        button.AutoButtonColor = false
        button.LayoutOrder = i
        button.Parent = CombatSlotsFrame
        addCorner(button, 6)
        combatSlotButtons[slotNumber] = button
        connect(button.MouseButton1Click, function()
            local chosen = combatSelectSlot(slotNumber)
            for slot, slotButton in pairs(combatSlotButtons) do
                local selected = chosen == slot
                slotButton.BackgroundColor3 = selected and Theme.Accent1 or Theme.BgSecondary
                slotButton.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or Theme.TextDim
            end
        end)
    end

    createCombatToggle(CombatPage, "CombatSkillToggleCard", "Auto Skills", 2, combatToggleAutoSkill)
    -- RANDOM HUB | Shared-style multi-select skills dropdown (black cards, blue selection).
    local function createRandomHubSkillDropdown(card, titleText, keys, selected, onChanged, onResized)
        card.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        card.ClipsDescendants = true
        local compactHeight = 58
        local listHeight = math.min(190, #keys * 35 + 12)
        local expandedHeight = compactHeight + listHeight + 8
        card.Size = UDim2.new(1, 0, 0, compactHeight)
    
        local open = false
        local header = Instance.new("TextButton")
        header.Name = "SelectSkillsDropdown"
        header.Size = UDim2.new(1, 0, 0, compactHeight)
        header.BackgroundTransparency = 1
        header.BorderSizePixel = 0
        header.TextColor3 = Theme.Text
        header.TextSize = 14
        header.Font = Enum.Font.GothamBold
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.TextTruncate = Enum.TextTruncate.AtEnd
        header.AutoButtonColor = false
        header.ZIndex = 4
        header.Parent = card
        local inset = Instance.new("UIPadding")
        inset.PaddingLeft = UDim.new(0, 16)
        inset.PaddingRight = UDim.new(0, 14)
        inset.Parent = header
    
        local options = Instance.new("ScrollingFrame")
        options.Name = "SelectSkillsOptions"
        options.Size = UDim2.new(1, -18, 0, listHeight)
        options.Position = UDim2.fromOffset(9, compactHeight)
        options.BackgroundColor3 = Color3.fromRGB(13, 13, 17)
        options.BorderSizePixel = 0
        options.ScrollBarThickness = 3
        options.ScrollBarImageColor3 = Theme.Accent2
        options.ScrollingDirection = Enum.ScrollingDirection.Y
        options.CanvasSize = UDim2.fromOffset(0, 0)
        options.Visible = false
        options.Active = true
        options.ZIndex = 5
        options.Parent = card
        addCorner(options, 9)
        addStroke(options, Theme.Stroke, 1, 0.45)
    
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = options
        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 6)
        padding.PaddingBottom = UDim.new(0, 6)
        padding.PaddingLeft = UDim.new(0, 6)
        padding.PaddingRight = UDim.new(0, 9)
        padding.Parent = options
    
        local rows = {}
        local function refresh()
            local names = {}
            for _, item in ipairs(keys) do
                local key = type(item) == "table" and item.Key or item
                local label = type(item) == "table" and (item.Label or tostring(key)) or tostring(key)
                if selected[key] == true then names[#names + 1] = label end
                local row = rows[key]
                if row then
                    row.BackgroundColor3 = selected[key] == true and Theme.Accent2 or Color3.fromRGB(24, 24, 29)
                    row.TextColor3 = selected[key] == true and Color3.fromRGB(255, 255, 255) or Theme.TextDim
                    row.Text = (selected[key] == true and "✓  " or "   ") .. label
                end
            end
            local suffix = #names > 0 and (": " .. table.concat(names, ", ")) or ""
            header.Text = titleText
        end
    
        for index, item in ipairs(keys) do
            local skillKey = type(item) == "table" and item.Key or item
            local skillLabel = type(item) == "table" and (item.Label or tostring(skillKey)) or tostring(skillKey)
            local option = Instance.new("TextButton")
            option.Name = "SkillOption_" .. skillLabel
            option.Size = UDim2.new(1, -3, 0, 31)
            option.LayoutOrder = index
            option.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
            option.BorderSizePixel = 0
            option.TextColor3 = Theme.TextDim
            option.Font = Enum.Font.GothamBold
            option.TextSize = 13
            option.TextXAlignment = Enum.TextXAlignment.Left
            option.AutoButtonColor = false
            option.ZIndex = 6
            option.Parent = options
            addCorner(option, 7)
            rows[skillKey] = option
            option.MouseButton1Click:Connect(function()
                selected[skillKey] = not (selected[skillKey] == true)
                refresh()
                if onChanged then onChanged(skillKey, selected[skillKey]) end
            end)
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            options.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
        end)
        options.CanvasSize = UDim2.fromOffset(0, #keys * 35 + 12)
        header.MouseButton1Click:Connect(function()
            open = not open
            options.Visible = open
            card.Size = UDim2.new(1, 0, 0, open and expandedHeight or compactHeight)
            refresh()
            if onResized then onResized(open and expandedHeight or compactHeight) end
        end)
        refresh()
        return refresh
    end
    local CombatSkillSelectionCard = createStyledCard(CombatPage, "CombatSkillSelectionCard", 58, 3)
    local combatSkillNames = {}
    for _, data in ipairs(SKILL_KEYS) do combatSkillNames[#combatSkillNames+1] = data.Key end
    createRandomHubSkillDropdown(CombatSkillSelectionCard, "Select Skills", combatSkillNames, CombatCfg.SelectedSkills)

    createCombatToggle(CombatPage, "CombatAttackToggleCard", "Auto Attack", 4, combatToggleAutoAttack)
end)

runSection("Teleport", function()
    local page = Pages.Teleport
    local presetIslands = {
        {name = "Starter Island", position = Vector3.new(275.05, 9.92, -861.51)},
        {name = "Jungle Island", position = Vector3.new(-847.60, 10.65, 77.97)},
        {name = "West Island", position = Vector3.new(712.07, 7.19, 2513.58)},
        {name = "Online Island", position = Vector3.new(3487.62, 32.22, 2540.20)},
        {name = "Sorcerers Island", position = Vector3.new(4291.62, 42.95, 753.31)},
        {name = "Good House", position = Vector3.new(2809.77, 11.57, -2676.01)},
    }
    World.travelPoints = presetIslands
    local palette = {
        surface = Color3.fromRGB(30, 30, 33),
        input = Color3.fromRGB(39, 39, 42),
        list = Color3.fromRGB(21, 21, 24),
        text = Color3.fromRGB(245, 245, 250),
        muted = Color3.fromRGB(174, 178, 191),
    }
    local container = createStyledCard(page, "IslandsCard", 152, 1)
    container.BackgroundColor3 = palette.list
    container.ZIndex = 4
    local label = Instance.new("TextLabel")
    label.Name = "IslandSectionTitle"
    label.Size = UDim2.new(1, -20, 0, 27)
    label.Position = UDim2.fromOffset(10, 8)
    label.BackgroundTransparency = 1
    label.Text = "Tp Island"
    label.TextColor3 = palette.text
    label.TextSize = 20
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local selection = Instance.new("TextButton")
    selection.Name = "SelectIsland"
    selection.Size = UDim2.new(1, -16, 0, 38)
    selection.Position = UDim2.fromOffset(8, 44)
    selection.BackgroundColor3 = palette.input
    selection.BorderSizePixel = 0
    selection.Text = "Select Island"
    selection.Font = Enum.Font.Gotham
    selection.TextSize = 13
    selection.TextColor3 = palette.text
    selection.TextXAlignment = Enum.TextXAlignment.Left
    selection.AutoButtonColor = true
    selection.ZIndex = 6
    selection.Parent = container
    addCorner(selection, 9)
    local selectionPadding = Instance.new("UIPadding")
    selectionPadding.PaddingLeft = UDim.new(0, 12)
    selectionPadding.PaddingRight = UDim.new(0, 12)
    selectionPadding.Parent = selection

    local teleportButton = Instance.new("TextButton")
    teleportButton.Name = "TeleportToIsland"
    teleportButton.Size = UDim2.new(1, -16, 0, 42)
    teleportButton.Position = UDim2.fromOffset(8, 93)
    teleportButton.BackgroundColor3 = palette.input
    teleportButton.BorderSizePixel = 0
    teleportButton.AutoButtonColor = true
    teleportButton.Font = Enum.Font.Gotham
    teleportButton.TextSize = 13
    teleportButton.TextColor3 = palette.text
    teleportButton.Text = "Teleport to Island     ›"
    teleportButton.ZIndex = 5
    teleportButton.Parent = container
    addCorner(teleportButton, 9)

    local popup = Instance.new("Frame")
    popup.Name = "IslandDropdown"
    popup.Size = UDim2.new(1, -16, 0, 196)
    popup.Position = UDim2.fromOffset(8, 85)
    popup.BackgroundColor3 = palette.list
    popup.BorderSizePixel = 0
    popup.ZIndex = 15
    popup.Visible = false
    popup.Parent = container
    addCorner(popup, 9)
    addStroke(popup, Color3.fromRGB(66, 67, 79), 1, 0.1)

    local scrolling = Instance.new("ScrollingFrame")
    scrolling.Name = "IslandChoices"
    scrolling.Size = UDim2.new(1, -12, 1, -12)
    scrolling.Position = UDim2.fromOffset(6, 6)
    scrolling.BackgroundTransparency = 1
    scrolling.BorderSizePixel = 0
    scrolling.ScrollBarThickness = 4
    scrolling.ScrollBarImageColor3 = Color3.fromRGB(59, 94, 198)
    scrolling.ScrollingDirection = Enum.ScrollingDirection.Y
    scrolling.CanvasSize = UDim2.fromOffset(0, 0)
    scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrolling.ZIndex = 16
    scrolling.Parent = popup
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scrolling

    local selected = nil
    local activeTeleport = false
    local choiceConnections = {}
    -- Use only the manually configured names and coordinates for this menu.
    -- The automatic island index remains available to other systems (e.g. Auto Farm).
    local islandCatalog = {}
    local seenNames = {}
    for _, preset in ipairs(presetIslands) do
        local key = preset.name:lower():gsub("%s+", " ")
        if not seenNames[key] then
            seenNames[key] = true
            islandCatalog[#islandCatalog + 1] = {
                name = preset.name,
                position = preset.position,
            }
        end
    end

    local function updateChoices()
        for _, connection in ipairs(choiceConnections) do pcall(function() connection:Disconnect() end) end
        table.clear(choiceConnections)
        for _, child in ipairs(scrolling:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local order = 0
        for _, info in ipairs(islandCatalog) do
            order = order + 1
            local choice = Instance.new("TextButton")
            choice.Name = "Island_" .. tostring(order)
            choice.Size = UDim2.new(1, -6, 0, 33)
            choice.LayoutOrder = order
            choice.BackgroundColor3 = palette.input
            choice.BorderSizePixel = 0
            choice.Text = info.name
            choice.TextColor3 = palette.muted
            choice.TextSize = 12
            choice.TextXAlignment = Enum.TextXAlignment.Left
            choice.Font = Enum.Font.Gotham
            choice.ZIndex = 17
            choice.Parent = scrolling
            addCorner(choice, 7)
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 12)
            pad.Parent = choice
            choiceConnections[#choiceConnections + 1] = choice.MouseButton1Click:Connect(function()
                selected = info
                selection.Text = info.name
                popup.Visible = false
            end)
        end
        if order == 0 then
            local empty = Instance.new("TextButton")
            empty.Name = "IslandEmpty"
            empty.LayoutOrder = 1
            empty.Size = UDim2.new(1, -6, 0, 33)
            empty.BackgroundColor3 = palette.input
            empty.BorderSizePixel = 0
            empty.Text = "No islands found"
            empty.TextColor3 = palette.muted
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.AutoButtonColor = false
            empty.ZIndex = 17
            empty.Parent = scrolling
        end
        scrolling.CanvasPosition = Vector2.new(0, 0)
    end

    local function openDropdown(state)
        popup.Visible = state
        if state then updateChoices() end
    end
    connect(selection.MouseButton1Click, function() openDropdown(not popup.Visible) end)
    Stoppers.IslandDropdown = function()
        for _, connection in ipairs(choiceConnections) do pcall(function() connection:Disconnect() end) end
        table.clear(choiceConnections)
    end
    connect(teleportButton.MouseButton1Click, function()
        if activeTeleport then return end
        if not selected then openDropdown(true); return end
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not root or not humanoid or humanoid.Health <= 0 then return end
        activeTeleport = true
        teleportButton.Text = "Loading island..."
        popup.Visible = false
        if QuestRuntime.StopItems then QuestRuntime.StopItems() end
        -- Motion.manual prefetches nearby map regions, then fades the loading cover.
        if not Motion.manual(CFrame.new(selected.position)) then
            activeTeleport = false
            teleportButton.Text = "Teleport unavailable — retry"
            task.delay(1.5, function()
                if not destroyed and teleportButton.Parent then teleportButton.Text = "Teleport to Island     ›" end
            end)
            return
        end
        -- Reactivate when the actual teleport task finishes, not on a fixed timer.
        task.spawn(function()
            while not destroyed and Motion.manualThread do task.wait(0.08) end
            activeTeleport = false
            if not destroyed and teleportButton.Parent then teleportButton.Text = "Teleport to Island     ›" end
        end)
    end)
end)

runSection("AutoChest", function()
    local AutoItemsPage = Pages.AutoItems
    local autoChestEnabled = false

    local AutoChestCard = createStyledCard(AutoItemsPage, "AutoChestCard", 48, 1)
    local AutoChestTitle = Instance.new("TextLabel")
    AutoChestTitle.Name = "AutoChestTitle"
    AutoChestTitle.Size = UDim2.new(1, -100, 0, 24)
    AutoChestTitle.Position = UDim2.new(0, 16, 0.5, -12)
    AutoChestTitle.BackgroundTransparency = 1
    AutoChestTitle.Text = "Auto Collect Chest"
    AutoChestTitle.TextColor3 = Theme.Text
    AutoChestTitle.Font = Enum.Font.GothamBold
    AutoChestTitle.TextSize = 15
    AutoChestTitle.TextXAlignment = Enum.TextXAlignment.Left
    AutoChestTitle.Parent = AutoChestCard

    local AutoChestDescription = Instance.new("TextLabel")
    AutoChestDescription.Size = UDim2.new(1, -100, 0, 18)
    AutoChestDescription.Position = UDim2.fromOffset(16, 31)
    AutoChestDescription.BackgroundTransparency = 1
    AutoChestDescription.Text = "Teleport to detected chests around the map"
    AutoChestDescription.Visible = false
    AutoChestDescription.TextColor3 = Theme.TextDim
    AutoChestDescription.Font = Enum.Font.Gotham
    AutoChestDescription.TextSize = 10
    AutoChestDescription.TextXAlignment = Enum.TextXAlignment.Left
    AutoChestDescription.Parent = AutoChestCard

    local AutoChestToggle = Instance.new("TextButton")
    AutoChestToggle.Name = "AutoChestToggle"
    AutoChestToggle.Size = UDim2.fromOffset(52, 28)
    AutoChestToggle.Position = UDim2.new(1, -68, 0, 15)
    AutoChestToggle.BackgroundColor3 = Color3.new(1, 1, 1)
    AutoChestToggle.BorderSizePixel = 0
    AutoChestToggle.Text = ""
    AutoChestToggle.AutoButtonColor = false
    AutoChestToggle.Parent = AutoChestCard
    addCorner(AutoChestToggle, 14)
    local AutoChestToggleStroke = addStroke(AutoChestToggle, Theme.Stroke, 1, 0.3)
    local AutoChestToggleGradient = Instance.new("UIGradient")
    AutoChestToggleGradient.Color = TOGGLE_OFF
    AutoChestToggleGradient.Parent = AutoChestToggle
    local AutoChestToggleKnob = Instance.new("Frame")
    AutoChestToggleKnob.Name = "Knob"
    AutoChestToggleKnob.Size = UDim2.fromOffset(22, 22)
    AutoChestToggleKnob.Position = UDim2.new(0, 3, 0.5, -11)
    AutoChestToggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    AutoChestToggleKnob.BorderSizePixel = 0
    AutoChestToggleKnob.Parent = AutoChestToggle
    addCorner(AutoChestToggleKnob, 11)

    local function renderAutoChestToggle()
        AutoChestToggleGradient.Color = autoChestEnabled and TOGGLE_ON or TOGGLE_OFF
        AutoChestToggleStroke.Transparency = autoChestEnabled and 0.6 or 0.3
        tween(AutoChestToggleKnob, {
            Position = autoChestEnabled and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11),
        }, 0.18)
    end

    local Items = {
        fruitEnabled = false, target = nil, generation = 0, actionToken = 0, nextSearch = 0,
        cooldowns = setmetatable({}, {__mode = "k"}), pending = setmetatable({}, {__mode = "k"}),
        regionCooldowns = {}, nextRegionAt = 0, nextRegionBuild = 0,
        observers = {},
        -- Armazenamento automatico: apenas frutas realmente recebidas nesta coleta.
        storeQueue = {}, storeSeen = setmetatable({}, {__mode = "k"}),
        storeWorker = nil, storeRetryWindow = 10,
        -- Apenas marcadores visuais: nao teleportar, coletar, equipar nem armazenar.
        fruitMarkers = {},
        lastMarkerRefresh = -math.huge,
        markerRefreshInterval = 0.65,
        storeAfterOne = false,
        -- Baús já visitados nesta ativação. Impede voltar sempre ao mesmo.
        fastChestVisited = setmetatable({}, {__mode = "k"}),
        fastChestPhase = nil,
        fastChestHoldUntil = nil,
        fastChestFound = false,
    }

    function Items.info(object, kind)
        if not object or not object.Parent or not object:IsDescendantOf(workspace) or World.held(object) then return nil end
        local candidate = object
        if kind == "fruit" then candidate = World.fruitPickup(object)
        elseif object:IsA("ProximityPrompt") then
            candidate = object:FindFirstAncestorWhichIsA("Model") or object:FindFirstAncestorWhichIsA("BasePart")
        end
        if not candidate or not candidate.Parent or World.held(candidate) or candidate:FindFirstChildOfClass("Humanoid") then return nil end
        if kind == "chest" then
            local node = candidate.Parent
            while node and node ~= workspace do
                if node:IsA("Model") and World.chestName(node.Name) then candidate = node; break end
                node = node.Parent
            end
            if not World.chestName(candidate.Name) then return nil end
            -- Do not repeatedly try chests known to be opened/collected.
            for _, attr in ipairs({"Opened", "IsOpened", "Collected", "Looted", "Taken"}) do
                if candidate:GetAttribute(attr) == true then return nil end
            end
        end
        local prompt = candidate:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and not prompt.Enabled then
            if kind == "fruit" then return nil end
            prompt = nil
        end
        local click = candidate:FindFirstChildWhichIsA("ClickDetector", true)
        local touch = candidate:FindFirstChildWhichIsA("TouchTransmitter", true)
        local part = candidate:IsA("BasePart") and candidate or nil
        if not part and prompt then part = prompt:FindFirstAncestorWhichIsA("BasePart") end
        if not part and click then part = click:FindFirstAncestorWhichIsA("BasePart") end
        if not part and touch and touch.Parent and touch.Parent:IsA("BasePart") then part = touch.Parent end
        part = part or candidate:FindFirstChild("Handle", true) or World.root(candidate)
        if not part or not part:IsA("BasePart") or not part.Parent then return nil end
        if kind == "fruit" then
            local node = candidate
            while node and node ~= workspace do
                local name = string.lower(node.Name)
                for _, hint in ipairs({"dealer", "shop", "merchant", "vendor"}) do
                    if name:find(hint, 1, true) then return nil end
                end
                if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return nil end
                node = node.Parent
            end
            local action = prompt and string.lower(prompt.ActionText) or ""
            if action:find("buy", 1, true) or action:find("purchase", 1, true) or action:find("comprar", 1, true) then return nil end
            if not World.fruitDisplay(candidate) then return nil end
            if not part.CanTouch and not prompt and not click then return nil end
        end
        if kind == "chest" and not prompt and not click and not part.CanTouch then return nil end
        return {object = candidate, part = part, prompt = prompt, click = click, touch = touch,
            kind = kind, name = kind == "fruit" and World.fruitDisplay(candidate) or candidate.Name}
    end

    -- Detected Fruit: os mesmos alvos que o coletor anterior reconhecia sao
    -- mostrados como marcadores no mundo, sem executar nenhuma acao no jogo.
    function Items.clearFruitMarkers()
        for part, marker in pairs(Items.fruitMarkers) do
            if marker.gui then pcall(function() marker.gui:Destroy() end) end
            Items.fruitMarkers[part] = nil
        end
    end

    function Items.newFruitMarker(part)
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RandomHubDetectedFruit"
        billboard.Adornee = part
        billboard.Size = UDim2.fromOffset(220, 65)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0 -- Sem limite de distancia para frutas replicadas no cliente.
        billboard.Parent = UIParent

        local panel = Instance.new("Frame")
        panel.Name = "Marker"
        panel.BackgroundColor3 = Color3.fromRGB(12, 17, 27)
        panel.BackgroundTransparency = 0.12
        panel.BorderSizePixel = 0
        panel.Size = UDim2.fromOffset(220, 55)
        panel.Parent = billboard
        addCorner(panel, 9)
        addStroke(panel, Theme.Accent2, 1.5, 0)

        local title = Instance.new("TextLabel")
        title.Name = "FruitName"
        title.Size = UDim2.new(1, -12, 0, 25)
        title.Position = UDim2.fromOffset(6, 4)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 15
        title.TextColor3 = Color3.fromRGB(255, 244, 155)
        title.TextStrokeColor3 = Color3.new(0, 0, 0)
        title.TextStrokeTransparency = 0.3
        title.Text = "Fruit"
        title.Parent = panel

        local detail = Instance.new("TextLabel")
        detail.Name = "Location"
        detail.Size = UDim2.new(1, -12, 0, 18)
        detail.Position = UDim2.fromOffset(6, 28)
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.TextSize = 12
        detail.TextColor3 = Color3.fromRGB(150, 204, 255)
        detail.TextStrokeColor3 = Color3.new(0, 0, 0)
        detail.TextStrokeTransparency = 0.35
        detail.Text = ""
        detail.Parent = panel
        return {gui = billboard, title = title, detail = detail}
    end

    function Items.updateFruitMarkers(now)
        if not Items.fruitEnabled then return end
        if now - Items.lastMarkerRefresh < Items.markerRefreshInterval then return end
        Items.lastMarkerRefresh = now
        local seenParts = {}
        local character = LocalPlayer.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")

        for object in pairs(World.fruits) do
            if not object or not object.Parent or not object:IsDescendantOf(workspace) then
                World.fruits[object] = nil
            else
                -- Reutiliza exatamente o reconhecimento do antigo coletor de frutas.
                local ok, info = pcall(Items.info, object, "fruit")
                if ok and info and info.part and info.part:IsDescendantOf(workspace) then
                    local part = info.part
                    seenParts[part] = true -- Unifica modelo, Part e prompt da mesma fruta.
                    local marker = Items.fruitMarkers[part]
                    if not marker or not marker.gui or not marker.gui.Parent then
                        marker = Items.newFruitMarker(part)
                        Items.fruitMarkers[part] = marker
                    end
                    local fruitName = tostring(info.name or "Unknown Fruit")
                    if not string.lower(fruitName):match("fruit$") then
                        fruitName = fruitName .. " Fruit"
                    end
                    marker.title.Text = fruitName
                    local position = part.Position
                    if playerRoot and playerRoot.Parent then
                        local studs = math.floor((playerRoot.Position - position).Magnitude + 0.5)
                        marker.detail.Text = tostring(studs) .. " studs  |  X: " .. math.floor(position.X)
                            .. "  Z: " .. math.floor(position.Z)
                    else
                        marker.detail.Text = "X: " .. math.floor(position.X) .. "  Z: " .. math.floor(position.Z)
                    end
                    marker.gui.Adornee = part
                end
            end
        end

        -- Fruta coletada/destruida/despawnada: marcador desaparece imediatamente.
        for part, marker in pairs(Items.fruitMarkers) do
            if not seenParts[part] or not part.Parent or not part:IsDescendantOf(workspace) then
                if marker.gui then pcall(function() marker.gui:Destroy() end) end
                Items.fruitMarkers[part] = nil
            end
        end
    end

    function Items.endTouch()
        local held = Items.touching
        Items.touching = nil
        if held and type(firetouchinterest) == "function" then pcall(firetouchinterest, held.root, held.part, 1) end
    end

    function Items.clear(reason, cooldown)
        Items.actionToken = Items.actionToken + 1
        if Items.heldPrompt then pcall(function() Items.heldPrompt:InputHoldEnd() end) end
        if Items.heldKey and VirtualInputManager then
            pcall(function() VirtualInputManager:SendKeyEvent(false, Items.heldKey, false, game) end)
        end
        Items.heldPrompt, Items.heldKey, Items.holdUntil = nil, nil, nil
        Items.endTouch()
        Items.fastChestPhase, Items.fastChestHoldUntil, Items.fastChestDestination = nil, nil, nil
        Items.safeChestDeadline = nil
        Motion.cancelLongTravel("Items")
        if Items.target and cooldown then Items.cooldowns[Items.target.object] = os.clock() + cooldown end
        Items.target, Items.startedAt, Items.interactedAt, Items.contactAt = nil, nil, nil, nil
        Items.missingFruitSince = nil
        Items.fruitArrivedAt = nil
        Items.lastResult, Items.attempts = reason, 0
        World.fruitScanActive, QuestRuntime.ItemBusy = false, false
        Motion.release("Items")
    end

    function Items.inventory()
        local result = {}
        local function add(container)
            if not container then return end
            for _, object in ipairs(container:GetChildren()) do if object:IsA("Tool") then result[object] = true end end
        end
        add(LocalPlayer:FindFirstChildOfClass("Backpack")); add(LocalPlayer.Character)
        return result
    end

    -- Diferencia fruta obtida agora de Tools que o jogador ja possuia.
    function Items.isFruitTool(tool, expected)
        if not tool or not tool.Parent or not tool:IsA("Tool") then return false end
        local name = World.fruitDisplay(tool) or World.fruitAlias(tool.Name)
        if not name then name = World.fruitAlias(tool.ToolTip) end
        local expectedName = World.fruitAlias(expected)
        if name and expectedName then return name == expectedName end
        if name then return true end
        -- Algumas frutas chegam com nome interno generico. Aceite somente
        -- durante uma coleta cuja recompensa foi confirmada pelo inventario.
        local key = World.fruitKey(tool.Name)
        return expected ~= nil and (key == "devilfruit" or key == "fruit")
    end

    function Items.storeButton()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return nil end
        local function visible(obj)
            local node = obj
            while node and node ~= playerGui do
                if node:IsA("GuiObject") and not node.Visible then return false end
                if node:IsA("ScreenGui") and not node.Enabled then return false end
                node = node.Parent
            end
            return node == playerGui
        end
        local function textOf(obj)
            local str = obj:IsA("TextButton") and obj.Text or obj.Name
            str = World.fruitKey(str)
            if str == "" or str == "textbutton" or str == "button" then
                for _, child in ipairs(obj:GetChildren()) do
                    if child:IsA("TextLabel") then str = World.fruitKey(child.Text); break end
                end
            end
            return str
        end
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("GuiButton") and object.Active ~= false
                and not object:IsDescendantOf(ScreenGui) and visible(object) then
                local action = textOf(object)
                if action == "store" or action == "storefruit" or action == "storefruits"
                    or action == "storeininventory" or action == "guardar" or action == "guardarfruta" then
                    local parent = object.Parent
                    local reject, context = false, false
                    local node = parent
                    for _ = 1, 5 do
                        if not node or node == playerGui then break end
                        local key = World.fruitKey(node.Name)
                        if key:find("shop", 1, true) or key:find("robux", 1, true)
                            or key:find("pass", 1, true) or key:find("purchase", 1, true)
                            or key:find("upgrade", 1, true) then reject = true; break end
                        if key:find("fruit", 1, true) or key:find("inventory", 1, true)
                            or key:find("item", 1, true) or key:find("tool", 1, true) then context = true end
                        node = node.Parent
                    end
                    -- Botao simplesmente "Store" so e confiavel quando o painel
                    -- tambem possui acao Eat/Drop da fruta (nao a loja de Robux).
                    if not context and parent then
                        for _, peer in ipairs(parent:GetDescendants()) do
                            if peer:IsA("GuiButton") and peer ~= object and visible(peer) then
                                local label = textOf(peer)
                                if label == "eat" or label == "eatfruit" or label == "drop"
                                    or label == "droptool" or label == "consume" then context = true; break end
                            end
                        end
                    end
                    if not reject and context then return object end
                end
            end
        end
    end

    function Items.storeClick(button)
        if not button or not button.Parent then return false end
        local center = button.AbsolutePosition + button.AbsoluteSize * 0.5
        if button.AbsoluteSize.X < 8 or button.AbsoluteSize.Y < 8 then return false end
        -- Prefere a mesma acao que o jogador usaria no botao Store da propria GUI.
        if VirtualInputManager then
            -- Nao deixar a propria janela do Random Hub interceptar o clique Store.
            local wasVisible = ScreenGui.Enabled
            ScreenGui.Enabled = false
            local clicked = pcall(function()
                VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
                VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            end)
            task.wait(0.08)
            pcall(function() VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0) end)
            ScreenGui.Enabled = wasVisible and not destroyed
            if clicked then return true end
        end
        return World.emit(button.MouseButton1Click) or World.emit(button.Activated, nil, 1)
    end

    function Items.queueFruitStorage(tool, expected)
        if not (Items.fruitEnabled or Items.storeAfterOne) or destroyed
            or not Items.isFruitTool(tool, expected) or Items.storeSeen[tool] then return end
        Items.storeSeen[tool] = true
        Items.storeQueue[#Items.storeQueue + 1] = {tool = tool, expected = expected, at = os.clock()}
        if Items.storeWorker then return end
        Items.storeWorker = task.spawn(function()
            while not destroyed and (Items.fruitEnabled or Items.storeAfterOne) and #Items.storeQueue > 0 do
                local entry = table.remove(Items.storeQueue, 1)
                local fruit = entry.tool
                local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
                local char = LocalPlayer.Character
                if fruit and fruit.Parent and ((backpack and fruit:IsDescendantOf(backpack))
                    or (char and fruit:IsDescendantOf(char))) then
                    local deadline = os.clock() + Items.storeRetryWindow
                    local attempted = false
                    local equippedByStore = false
                    local previousTool
                    local character = LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    -- Evita interromper dialogos de quest ou compras no mesmo instante.
                    while os.clock() < deadline and not destroyed
                        and (Items.fruitEnabled or Items.storeAfterOne) do
                        if not fruit.Parent then break end
                        if QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving or QuestRuntime.FruitBuying
                            or QuestRuntime.SkillBusy or QuestRuntime.Farming then
                            task.wait(0.35)
                        else
                            if humanoid and humanoid.Health > 0 and character == LocalPlayer.Character
                                and fruit.Parent ~= character and not equippedByStore then
                                previousTool = character:FindFirstChildOfClass("Tool")
                                local ok = pcall(function() humanoid:EquipTool(fruit) end)
                                equippedByStore = ok
                                task.wait(0.35)
                            end
                            if fruit.Parent == character then
                                local button = Items.storeButton()
                                if button then
                                    attempted = Items.storeClick(button)
                                    task.wait(0.8)
                                    if not fruit.Parent or (backpack and not fruit:IsDescendantOf(backpack)
                                        and not fruit:IsDescendantOf(character)) then break end
                                    -- Uma unica interacao confirmada; nao repetir cliques cegamente.
                                    break
                                end
                            end
                            task.wait(0.25)
                        end
                    end
                    if humanoid and humanoid.Parent and previousTool and previousTool.Parent
                        and previousTool ~= fruit and previousTool:IsA("Tool") then
                        pcall(function() humanoid:EquipTool(previousTool) end)
                    elseif equippedByStore and fruit.Parent == character and humanoid and humanoid.Parent then
                        -- Se o jogo nao oferecer Store, devolve a fruta a mochila sem consumir.
                        pcall(function() humanoid:UnequipTools() end)
                    end
                    if fruit.Parent and not attempted then
                        warn("[Random Hub | Auto Collect Fruit] Fruta na mochila, mas nenhuma opcao Store Fruit foi encontrada; mantendo a fruta sem consumir.")
                    end
                end
                task.wait(0.3)
            end
            Items.storeWorker = nil
            -- Encerrada a unica tentativa de armazenamento desta ativacao.
            Items.storeAfterOne = false
        end)
    end

    function Items.queueNewCollectedFruit(info)
        if not info or info.kind ~= "fruit" then return end
        for tool in pairs(Items.inventory()) do
            if not (Items.beforeInventory and Items.beforeInventory[tool])
                and Items.isFruitTool(tool, info.name) then
                Items.queueFruitStorage(tool, info.name)
            end
        end
    end

    function Items.collected(info)
        local object, backpack, character = info.object, LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character
        if info.kind == "chest" then
            if not object.Parent or not object:IsDescendantOf(workspace) then return true end
            if Items.contactAt then
                for _, attr in ipairs({"Opened", "IsOpened", "Collected", "Looted", "Taken"}) do
                    if object:GetAttribute(attr) == true then return true end
                end
                if info.prompt and not info.prompt.Enabled then return true end
            end
            return false
        end
        if object.Parent and ((backpack and object:IsDescendantOf(backpack)) or (character and object:IsDescendantOf(character))) then return true end
        if not Items.contactAt then return false end
        for tool in pairs(Items.inventory()) do
            if not Items.beforeInventory[tool] then
                if World.fruitKey(tool.Name) == World.fruitKey(info.name) then return true end
                local expected = info.kind == "fruit" and World.fruitAlias(info.name)
                if expected and (World.fruitAlias(tool.Name) == expected or World.fruitAlias(tool.ToolTip) == expected) then return true end
            end
        end
        return false
    end

    function Items.click(info)
        if type(fireclickdetector) == "function" and pcall(fireclickdetector, info.click) then return true end
        local camera = workspace.CurrentCamera
        if not camera or not info.part.Parent then return false end
        local part = info.click:FindFirstAncestorWhichIsA("BasePart") or info.part
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
        local point, visible = camera:WorldToViewportPoint(part.Position)
        if not visible or point.Z <= 0 then return false end
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        local enabled = ScreenGui.Enabled
        ScreenGui.Enabled = false
        local ok = pcall(function()
            VirtualInputManager:SendMouseMoveEvent(point.X, point.Y, game)
            VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
        end)
        pcall(function() VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0) end)
        ScreenGui.Enabled = enabled and not destroyed
        return ok
    end

    function Items.forget(object)
        local observers = Items.observers[object]
        if observers then
            for _, connection in ipairs(observers) do connection:Disconnect() end
            Items.observers[object] = nil
        end
        Items.pending[object] = nil
    end

    function Items.observe(object)
        if Items.observers[object] then return end
        local properties = nil
        if object:IsA("Tool") then properties = {"Name"}
        elseif object:IsA("ProximityPrompt") then properties = {"ObjectText", "ActionText"}
        elseif object:IsA("TextLabel") and object:FindFirstAncestorWhichIsA("BillboardGui") then
            properties = {"Text"}
        end
        if not properties then return end
        local observers = {}
        Items.observers[object] = observers
        for _, property in ipairs(properties) do
            observers[#observers + 1] = object:GetPropertyChangedSignal(property):Connect(function()
                if not Items.fruitEnabled or destroyed or not object.Parent
                    or not object:IsDescendantOf(workspace) then return end
                if World.indexFruit(object) then Items.nextSearch = 0 end
            end)
        end
    end

    function Items.schedule(object)
        if not Items.fruitEnabled or not object or not object.Parent then return end
        Items.observe(object)
        if object:IsA("Model") or object:IsA("Tool") or object:IsA("BasePart") then
            Items.pending[object] = {at = os.clock() + 0.4, retries = 0}
        elseif object:IsA("ProximityPrompt") or object:IsA("ClickDetector") or object:IsA("TouchTransmitter") then
            World.indexFruit(object)
        end
    end

    function Items.drainPending(now)
        local count = 0
        for object, entry in pairs(Items.pending) do
            if not object.Parent then Items.pending[object] = nil
            elseif now >= entry.at then
                if World.indexFruit(object) then Items.nextSearch = 0 end
                entry.retries = entry.retries + 1
                if entry.retries >= 2 then Items.pending[object] = nil else entry.at = now + 1 end
                count = count + 1
                if count >= 100 then break end
            end
        end
    end

    function Items.scanExisting(token)
        local stack, processed = workspace:GetChildren(), 0
        while #stack > 0 do
            if destroyed or token ~= Items.generation or (not Items.fruitEnabled and not autoChestEnabled) then return end
            local object = table.remove(stack)
            if object.Parent then
                if Items.fruitEnabled then
                    Items.observe(object)
                    World.indexFruit(object)
                end
                if autoChestEnabled and (object:IsA("Model") or object:IsA("BasePart"))
                    and World.chestName(object.Name) then World.chests[object] = true end
                for _, child in ipairs(object:GetChildren()) do stack[#stack + 1] = child end
            end
            processed = processed + 1
            if processed % 300 == 0 then task.wait() end
        end
        Items.rescanNeeded = false
    end

    function Items.find(now, root)
        local best, distance, seen = nil, math.huge, {}
        local function consider(object, kind)
            if now < (Items.cooldowns[object] or 0) then return end
            local info = Items.info(object, kind)
            if not info or seen[info.object] or now < (Items.cooldowns[info.object] or 0)
                or (kind ~= "chest" and (now < (Motion.blocked[info.part] or 0)
                    or now < (Motion.blocked[info.object] or 0)))
                or (kind == "chest" and Items.fastChestVisited[info.object]) then return end
            seen[info.object] = true
            local d = (root.Position - info.part.Position).Magnitude
            if d < distance then best, distance = info, d end
        end
        if autoChestEnabled then
            for object in pairs(World.chests) do consider(object, "chest") end
        end
        return best
    end

    function Items.regions(now)
        if Items.regionPoints and now < Items.nextRegionBuild then return Items.regionPoints end
        local points = {}
        local function add(position)
            if not position then return end
            for _, point in ipairs(points) do if (point.position - position).Magnitude < 180 then return end end
            points[#points + 1] = {position = position}
        end
        for _, point in ipairs(World.travelPoints or {}) do add(point.position) end
        for island in pairs(World.islands) do add(World.islandPosition(island)) end
        table.sort(points, function(a, b)
            if a.position.X ~= b.position.X then return a.position.X < b.position.X end
            return a.position.Z < b.position.Z
        end)
        for _, point in ipairs(points) do point.key = math.floor(point.position.X / 180) .. ":" .. math.floor(point.position.Z / 180) end
        Items.regionPoints, Items.nextRegionBuild = points, now + 20
        return points
    end

    function Items.scanRegion(now)
        if not autoChestEnabled or not workspace.StreamingEnabled or now < Items.nextRegionAt
            or autoQuestEnabled or ManualFlight.Enabled or os.clock() < Motion.manualUntil
            or World.farmSearchActive or Motion.streamPending or type(LocalPlayer.RequestStreamAroundAsync) ~= "function" then return end
        local chosen
        for _, point in ipairs(Items.regions(now)) do
            if now >= (Items.regionCooldowns[point.key] or 0) then chosen = point; break end
        end
        Items.nextRegionAt = now + 3
        if not chosen then return end
        Items.regionCooldowns[chosen.key] = now + 35
        local token, action = Items.generation, Items.actionToken
        World.fruitScanActive = true
        local completed = false
        task.spawn(function()
            pcall(function() LocalPlayer:RequestStreamAroundAsync(chosen.position, 1.5) end)
            completed = true
        end)
        local started = os.clock()
        while not completed and os.clock() - started < 1.2 do
            if destroyed or token ~= Items.generation or action ~= Items.actionToken then
                World.fruitScanActive = false
                return
            end
            task.wait(0.1)
        end
        World.fruitScanActive = false
        if destroyed or (not Items.fruitEnabled and not autoChestEnabled)
            or token ~= Items.generation or action ~= Items.actionToken then return end
        Items.nextSearch = 0
    end

    -- AUTO CHEST INSTANTANEO: um teleporte por baú detectado, sem animação de voo,
    -- sem cooldown entre destinos e sem pedir streaming antes de cada teleporte.
    -- A interação ocorre no frame seguinte para que o cliente atualize a posição.
    -- Se um prompt exige segurar a tecla, respeita SOMENTE a duração desse hold.
    function Items.fastChestTick(now, character, root)
        local info = Items.target
        if info then
            if Items.collected(info) or not info.object.Parent or not info.object:IsDescendantOf(workspace) then
                Items.fastChestVisited[info.object] = true
                Items.clear("chest-finished")
                Items.nextSearch = 0
                return
            end
            local renewed = Items.info(info.object, "chest")
            if not renewed then
                Items.fastChestVisited[info.object] = true
                Items.clear("chest-unavailable")
                Items.nextSearch = 0
                return
            end
            info = renewed
            Items.target = info
        else
            -- Sem espera entre um baú já tentado e o próximo da lista.
            info = Items.find(now, root)
            Items.fastChestFound = info ~= nil
            if not info then
                Items.nextSearch = now
                Items.scanRegion(now) -- Tenta descobrir regiões ainda não replicadas.
                return
            end
            Items.target = info
            Items.startedAt, Items.attempts = now, 0
            Items.contactAt, Items.interactedAt = nil, nil
            Items.fastChestPhase = "teleport"
            Items.fastChestHoldUntil = nil
        end

        if SafeMode.Enabled and (Items.fastChestPhase == "teleport" or Items.fastChestPhase == "walk") then
            Items.fastChestPhase = "walk"
            Items.safeChestDeadline = Items.safeChestDeadline or (now + math.clamp((root.Position - info.part.Position).Magnitude / math.max(1, SafeMode.walkSpeed()) + 45, 35, 600))
            if now > Items.safeChestDeadline then
                Items.fastChestVisited[info.object] = true
                Items.clear("unreachable")
                return
            end
            local interactive = info.prompt ~= nil or info.click ~= nil
            if not Motion.request("Items", info.part, interactive and 1 or 0, "item") then
                Items.clear("paused"); return
            end
            QuestRuntime.ItemBusy = true
            local range = info.prompt and math.min(5, info.prompt.MaxActivationDistance)
                or (info.click and math.min(5, info.click.MaxActivationDistance)) or 3.5
            if (root.Position - info.part.Position).Magnitude > range then return end
            Motion.release("Items")
            Items.fastChestPhase = "interact"
            return
        elseif Items.fastChestPhase == "walk" then
            Items.fastChestPhase = "teleport"
        end

        if Items.fastChestPhase == "teleport" then
            -- Remove qualquer movimento anterior (farm, voo) antes do TP direto.
            Motion.release()
            QuestRuntime.ItemBusy = true
            local part = info.part
            local point = part.Position
            local direction = root.Position - point
            direction = Vector3.new(direction.X, 0, direction.Z)
            if direction.Magnitude < 0.05 then direction = Vector3.new(0, 0, 1) end
            direction = direction.Unit
            local interactive = info.prompt ~= nil or info.click ~= nil
            local targetPosition = point + direction * (interactive and 1.5 or 0.45)
                + Vector3.new(0, interactive and 1.15 or 0.25, 0)
            local facing = CFrame.lookAt(targetPosition, point)
            local moved = Motion.pivotDirect(character, root, facing)
            Items.fastChestDestination = facing.Position
            Items.fastChestPhase = moved and "interact" or "waitTeleport"
            return
        end

        if Items.fastChestPhase == "waitTeleport" then
            if Motion.longTravel and Motion.longTravel.owner == "Items" then return end
            local point = Items.fastChestDestination
            if point and (root.Position - point).Magnitude <= 9 then
                Items.fastChestPhase = "interact"
            else
                Items.fastChestPhase = "teleport"
            end
            return
        end

        QuestRuntime.ItemBusy = true
        if Items.fastChestPhase == "touching" then
            -- Mantém o toque durante um frame de física antes de soltá-lo.
            Items.endTouch()
            Items.fastChestPhase = "finish"
            return
        end
        if Items.fastChestPhase == "holding" then
            if now < (Items.fastChestHoldUntil or 0) then return end
            if Items.heldPrompt then pcall(function() Items.heldPrompt:InputHoldEnd() end) end
            if Items.heldKey and VirtualInputManager then
                pcall(function() VirtualInputManager:SendKeyEvent(false, Items.heldKey, false, game) end)
            end
            Items.heldPrompt, Items.heldKey = nil, nil
            Items.fastChestPhase = "finish"
            return
        end

        if Items.fastChestPhase == "interact" then
            local started = false
            Items.contactAt = now
            if info.prompt and info.prompt.Enabled then
                if type(fireproximityprompt) == "function" then
                    started = pcall(fireproximityprompt, info.prompt)
                end
                if not started then
                    started = pcall(function() info.prompt:InputHoldBegin() end)
                    if started then
                        Items.heldPrompt = info.prompt
                        Items.fastChestHoldUntil = now + math.max(0.08, info.prompt.HoldDuration + 0.04)
                        Items.fastChestPhase = "holding"
                        return
                    end
                end
            end
            if not started and info.click then started = Items.click(info) end
            if not started and info.part.CanTouch then
                if type(firetouchinterest) == "function" then
                    started = pcall(function() firetouchinterest(root, info.part, 0) end)
                    if started then
                        Items.touching = {root = root, part = info.part}
                        Items.fastChestPhase = "touching"
                        return
                    end
                end
                if not started then
                    -- Contato físico, sem invocar interações de objetos desconhecidos.
                    started = pcall(function()
                        Motion.pivotDirect(character, root, CFrame.new(info.part.Position + Vector3.new(0, 0.25, 0)))
                    end)
                end
            end
            Items.fastChestPhase = "finish"
            return
        end

        if Items.fastChestPhase == "finish" then
            -- Evita revisitar o mesmo baú na mesma ativação, mesmo que o servidor
            -- demore a remover seu modelo. O próximo TP é no próximo frame.
            Items.fastChestVisited[info.object] = true
            Items.clear("chest-visited")
            Items.nextSearch = 0
            return
        end
        Items.fastChestPhase = "teleport"
    end

    function Items.tick(now)
        -- Marcadores nao dependem de movimento nem da disponibilidade da quest.
        if Items.fruitEnabled then
            Items.drainPending(now)
            Items.updateFruitMarkers(now)
        end
        if not autoChestEnabled then return end
        if QuestRuntime.FruitBuying then return end
        if autoQuestEnabled or not Motion.allowed("Items") then Items.clear("paused"); return end
        if not World.ready then return end
        local character, root = Motion.character()
        if not character then Items.clear("respawn"); return end
        -- Todos os baús: teleporte direto, sem atrasos artificiais entre alvos.
        -- Mantém a prioridade do Auto Quest e não altera Detected Fruit.
        if autoChestEnabled then
            Items.fastChestTick(now, character, root)
            return
        end
        -- Fluxo antigo mantido abaixo apenas como referência para outros tipos.
        local info = Items.target
        if info then
            if Items.collected(info) then
                -- Baus coletados ou abertos deixam de ser alvos para movimento.
                Items.clear("collected-elsewhere", 18)
                Items.nextSearch = now + 0.25
                return
            end
            if not info.object.Parent or not info.object:IsDescendantOf(workspace) then
                Items.clear("unavailable", info.kind == "fruit" and 12 or nil)
                Items.nextSearch = now + 0.25
                return
            end
            local previousInfo = info
            info = Items.info(previousInfo.object, previousInfo.kind)
            if not info then
                Items.clear("invalid", previousInfo.kind == "fruit" and 12 or 8)
                Items.nextSearch = now + 0.25
                return
            end
            Items.missingFruitSince = nil
            Items.target = info
        elseif now >= Items.nextSearch then
            Items.nextSearch = now + 0.8
            info = Items.find(now, root)
            if not info then Items.scanRegion(now); return end
            Items.target, Items.startedAt, Items.attempts = info, now, 0
            Items.beforeInventory, Items.contactAt = Items.inventory(), nil
            Items.fruitArrivedAt = nil
        else return end
        if now - Items.startedAt > 24 then
            Items.clear("timeout", info.kind == "fruit" and 12 or 20)
            Items.nextSearch = now + 0.25
            return
        end
        -- Somente baus usam movimento automatico; frutas tem apenas marcadores.
        local spacing = (info.prompt or info.click) and 1 or 0
        -- Always use the actual interaction part. The model's default root can be
        -- far away from a chest's touch/prompt hitbox.
        local target = info.part
        if not Motion.request("Items", target, spacing, "item") then
            Items.clear("blocked", 4)
            Items.nextSearch = now + 0.25
            return
        end
        QuestRuntime.ItemBusy = true
        local range = info.prompt and math.min(5, info.prompt.MaxActivationDistance)
            or (info.click and math.min(5, info.click.MaxActivationDistance)) or 3
        if (root.Position - info.part.Position).Magnitude > range then return end
        Items.contactAt = Items.contactAt or now
        if Items.heldPrompt or Items.heldKey then
            if now >= (Items.holdUntil or 0) then
                if Items.heldPrompt then pcall(function() Items.heldPrompt:InputHoldEnd() end) end
                if Items.heldKey and VirtualInputManager then
                    pcall(function() VirtualInputManager:SendKeyEvent(false, Items.heldKey, false, game) end)
                end
                Items.heldPrompt, Items.heldKey, Items.holdUntil = nil, nil, nil
                Items.interactedAt = now
            end
            return
        end
        if Items.interactedAt and now - Items.interactedAt < 1.5 then return end
        if Items.attempts >= 5 then
            Items.clear("unconfirmed", 20)
            return
        end
        Items.attempts, Items.interactedAt = Items.attempts + 1, now
        if info.prompt then
            if info.prompt.HoldDuration > 12 then
                Items.clear("hold-too-long", 30)
                return
            end
            -- No primeiro disparo tenta fireproximityprompt; se nao houver coleta
            -- confirmada, as tentativas seguintes usam E/hold mesmo quando o
            -- executor retorna sucesso aparente sem acionar o servidor.
            local tryNative = Items.attempts == 1 or Items.attempts == 4
            local fired = tryNative and type(fireproximityprompt) == "function"
                and pcall(fireproximityprompt, info.prompt)
            if not fired then
                -- Depois da primeira tentativa nativa, alterna hold e tecla E
                -- (ou a tecla real indicada pelo prompt), com pressionar/soltar.
                local useKey = Items.attempts % 2 == 0 and VirtualInputManager ~= nil
                local key = info.prompt.KeyboardKeyCode
                if useKey and key ~= Enum.KeyCode.Unknown then
                    local down = pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
                    if down then
                        Items.heldKey = key
                        Items.holdUntil = now + math.max(0.14, info.prompt.HoldDuration + 0.08)
                    else useKey = false end
                else useKey = false end
                if not useKey then
                    local began = pcall(function() info.prompt:InputHoldBegin() end)
                    if began then
                        Items.heldPrompt, Items.holdUntil = info.prompt, now + math.max(0.1, info.prompt.HoldDuration + 0.08)
                    else
                        Items.clear("prompt-unavailable", 12)
                    end
                end
            end
        elseif info.click then Items.click(info)
        elseif info.kind == "chest" and info.part.CanTouch then
            local token, action = Items.generation, Items.actionToken
            if type(firetouchinterest) == "function" then
                Items.touching = {root = root, part = info.part}
                local ok = pcall(firetouchinterest, root, info.part, 0)
                if ok then task.wait(0.07) end
                if token == Items.generation and action == Items.actionToken then Items.endTouch() end
            else
                -- Standard physics contact fallback when the executor cannot fire touch events.
                pcall(function()
                    Motion.pivotDirect(character, root, CFrame.new(info.part.Position + Vector3.new(0, 0.6, 0)))
                end)
            end
        end
    end

    function Items.restart()
        Items.generation = Items.generation + 1
        Items.clear("stopped")
        if Items.worker then pcall(task.cancel, Items.worker); Items.worker = nil end
        World.onFruitAdded, World.onFruitRemoved = nil, nil
        for object, observers in pairs(Items.observers) do
            for _, connection in ipairs(observers) do connection:Disconnect() end
            Items.observers[object] = nil
        end
        Items.pending = setmetatable({}, {__mode = "k"})
        -- O toggle Detected Fruit nao enfileira armazenamento automatico.
        if not Items.fruitEnabled then Items.storeQueue = {} end
        if not Items.fruitEnabled then Items.clearFruitMarkers() end
        if destroyed or (not autoChestEnabled and not Items.fruitEnabled) then return end
        local token = Items.generation
        Items.nextSearch, Items.nextRegionAt, Items.rescanNeeded = 0, 0, (Items.fruitEnabled or autoChestEnabled)
        if Items.fruitEnabled then World.onFruitAdded, World.onFruitRemoved = Items.schedule, Items.forget end
        Items.worker = task.spawn(function()
            while not destroyed and token == Items.generation and (autoChestEnabled or Items.fruitEnabled) do
                local ok = pcall(function()
                    if Items.rescanNeeded and World.ready then Items.scanExisting(token) end
                    Items.tick(os.clock())
                end)
                if not ok then Items.clear("error", 10) end
                -- Uma passagem por frame enquanto há baús: nenhum delay entre TPs.
                -- Sem alvo, varredura leve para não sobrecarregar o jogo.
                task.wait(autoChestEnabled and (SafeMode.Enabled and 0.15 or (Items.fastChestFound and 0 or 0.2)) or 0.6)
            end
        end)
    end

    local function setAutoChestEnabled(state)
        local wasEnabled = autoChestEnabled
        autoChestEnabled = state == true
        if autoChestEnabled and not wasEnabled then
            Items.fastChestVisited = setmetatable({}, {__mode = "k"})
            Items.fastChestFound = false
        end
        renderAutoChestToggle()
        Items.restart()
    end
    connect(AutoChestToggle.MouseButton1Click, function() setAutoChestEnabled(not autoChestEnabled) end)
    createCombatToggle(Pages.Fruit, "DetectedFruitCard", "Detected Fruit", 2, function(state)
        -- Liga e desliga apenas marcadores no mapa; sem teleporte/interacao/coleta.
        Items.fruitEnabled = state == true
        Items.lastMarkerRefresh = -math.huge
        Items.restart()
    end)
    QuestRuntime.StopItems = function() Items.clear("preempted") end
    Stoppers.AutoItems = function()
        autoChestEnabled, Items.fruitEnabled = false, false
        Items.restart()
        Items.clearFruitMarkers()
    end

end)

runSection("AutoQuest", function()
    local Q = {
        repeatEnabled = false, generation = 0, phase = "SEEK", nextAction = 0,
        nextGuiScan = 0, nextWorldScan = 0,
        searchRadius = 500, searchRadiusSquared = 500 * 500,
        mobs = {}, names = {}, givers = {}, texts = {}, buttons = {},
        mobAliases = setmetatable({}, {__mode = "k"}),
        interactableCache = setmetatable({}, {__mode = "k"}),
        notices = {}, seenNotices = setmetatable({}, {__mode = "k"}),
        buttonCooldowns = setmetatable({}, {__mode = "k"}),
        target = nil, objective = nil, giver = nil, lastGiver = nil,
        questGiver = nil, returnCFrame = nil, progressSeen = nil, required = nil,
        pendingDeaths = 0, awaitingNewQuest = false,
        lastObjectiveAt = 0, interactedAt = nil, acceptedAt = nil,
        attempts = 0, lastErrorAt = -math.huge,
    }

    function Q.normalize(value)
        local text = tostring(value or ""):gsub("<[^>]*>", "")
        text = text:gsub("&apos;", "'"):gsub("&#39;", "'"):gsub("&quot;", '"'):gsub("&amp;", "&")
        text = text:gsub("’", "'"):gsub("‘", "'")
        return (string.lower(text):gsub("%s+", " "):match("^%s*(.-)%s*$"))
    end

    function Q.cleanLevels(value)
        local text = Q.normalize(value)
        for _, word in ipairs({"lv", "lvl", "level", "nivel", "nível"}) do
            text = text:gsub("%[" .. word .. "%.?%s*:?%s*%d+%]", " ")
                :gsub("%(" .. word .. "%.?%s*:?%s*%d+%)", " ")
                :gsub("%f[%a]" .. word .. "%.?%s*:?%s*%d+%f[%D]", " ")
        end
        return text
    end

    function Q.key(value)
        local text = Q.cleanLevels(value)
        text = text:gsub("'s%f[%A]", ""):gsub("'", "")
        for accent, plain in pairs({["á"]="a", ["à"]="a", ["ã"]="a", ["â"]="a", ["é"]="e", ["ê"]="e", ["í"]="i", ["ó"]="o", ["ô"]="o", ["õ"]="o", ["ú"]="u", ["ç"]="c"}) do
            text = text:gsub(accent, plain)
        end
        text = text:gsub("[^%w%s]", " "):gsub("%s+", " ")
        text = text:match("^%s*(.-)%s*$")
        local prefix, last = text:match("^(.-)(%S+)$")
        if not last then return "" end
        if last:match("ies$") and #last > 3 then last = last:sub(1, -4) .. "y"
        elseif last:match("sses$") or last:match("ches$") or last:match("shes$")
            or last:match("xes$") or last:match("zes$") then last = last:sub(1, -3)
        elseif #last > 3 and last:match("s$") and not last:match("ss$")
            and not last:match("us$") and not last:match("is$") then last = last:sub(1, -2) end
        return prefix .. last
    end

    function Q.progress(text)
        text = Q.normalize(text)
        local current, required = text:match("(%d+)%s*/%s*(%d+)")
        if not current then current, required = text:match("(%d+)%s+of%s+(%d+)") end
        if not current then current, required = text:match("(%d+)%s+de%s+(%d+)") end
        current, required = tonumber(current), tonumber(required)
        if required and required > 0 then return current, required, true end
        local tail = Q.verbTail(text)
        local amount = tail and tail:match("^(%d+)%s+%a")
            or text:match("%s+x%s*(%d+)%s*$") or text:match("^(%d+)%s*x%s+%a")
        amount = tonumber(amount)
        if amount and amount > 0 then return 0, amount, false end
        return nil, nil
    end

    function Q.hasQuestCue(text)
        text = Q.normalize(text)
        return text:find("quest", 1, true) or text:find("mission", 1, true)
            or text:find("objective", 1, true) or text:find("missao", 1, true)
            or text:find("missão", 1, true) or text:find("objetivo", 1, true)
    end

    function Q.verbTail(text)
        for _, verb in ipairs({"defeat", "kill", "eliminate", "slay", "hunt", "destroy", "derrote", "derrotar", "mate", "matar"}) do
            local _, finish = text:find("%f[%a]" .. verb .. "%f[%A]")
            if finish then return (text:sub(finish + 1):gsub("^%s+", "")) end
        end
        return nil
    end

    function Q.targetPhrase(text, allowPlain, allowUnknown)
        text = Q.cleanLevels(text)
        local phrase = Q.verbTail(text)
        local explicit = phrase ~= nil
        local strength = explicit and 3 or 1
        if not phrase then
            for _, label in ipairs({"npc name", "mob name", "enemy name", "target name", "npcname", "mobname", "enemyname", "targetname", "nome do npc", "npc", "npcs", "mob", "mobs", "enemy", "enemies", "target", "targets", "alvo", "inimigo"}) do
                phrase = text:match("^" .. label .. "%s*[:=%-]%s*(.+)$")
                if phrase then explicit, strength = true, 4; break end
            end
        end
        if not phrase then
            for _, suffix in ipairs({"defeated", "killed", "slain", "derrotados", "derrotado", "abatidos", "abatido"}) do
                phrase = text:match("^(.-)%s+" .. suffix .. "%f[%A]")
                if phrase then explicit, strength = true, 3; break end
            end
        end
        if not phrase then
            if not allowPlain then return nil end
            phrase = text
        end
        phrase = phrase:gsub("%d+%s*/%s*%d+", " ")
            :gsub("%d+%s+of%s+%d+", " "):gsub("%d+%s+de%s+%d+", " ")
        phrase = phrase:gsub("%s+for%s+.*$", ""):gsub("%s+reward.*$", "")
            :gsub("%s+progress.*$", ""):gsub("%s+remaining.*$", "")
        phrase = phrase:gsub("%b()", " "):gsub("%b[]", " ")
            :gsub("%s+x%s*%d+%s*$", ""):gsub("^%d+%s*x%s+", "")
        phrase = phrase:gsub("^%s*the%s+", ""):gsub("^%s*all%s+", "")
        if explicit then phrase = phrase:gsub("^%s*%d+%s+", ""):gsub("^%s*the%s+", "") end
        phrase = phrase:gsub("[%s%p]+$", ""):gsub("^%s+", "")
        local key = Q.key(phrase)
        local noise = {the=true, all=true, enemy=true, npc=true, mob=true, quest=true, objective=true,
            mission=true, missao=true, objetivo=true, recompensa=true, abate=true, progresso=true, quantidade=true, restante=true,
            status=true, ["quest status"]=true, target=true, progress=true, kill=true, killed=true,
            defeat=true, required=true, current=true, count=true, completed=true, complete=true,
            ["quest completed"]=true, ["quest complete"]=true, ["next quest"]=true, ["quest giver"]=true}
        if key == "" or #key > 80 or noise[key] or not key:find("%a")
            or key:find("%f[%a]reward%f[%A]") or key:match("^quest%s")
            or key:match("^level%s") or key:match("^health%s") or key:match("^hp%s")
            or key:match("^gold%s") or key:match("^coin%s") or key:match("^xp%s")
            or key:match("^required%s") or key:match("^progress%s") or key:match("^kill%s") then return nil end
        if not explicit and not Q.names[key] and not allowUnknown then return nil end
        if Q.names[key] and strength < 2 then strength = 2 end
        return Q.names[key] or phrase, explicit == true, strength
    end

    function Q.isText(object)
        return object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")
    end

    function Q.isOwnGui(object)
        return object == ScreenGui or object:IsDescendantOf(ScreenGui)
            or object:FindFirstAncestor("FlyToggle") ~= nil
    end

    function Q.visible(object, worldMarker)
        if not object or not object.Parent or Q.isOwnGui(object) then return false end
        local node = object
        while node and node ~= game do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("LayerCollector") and not node.Enabled then return false end
            node = node.Parent
        end
        if worldMarker then return true end
        if not object:IsA("GuiObject") or object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then return false end
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local pos, size = object.AbsolutePosition, object.AbsoluteSize
        local left, top, right, bottom = math.max(0, pos.X), math.max(0, pos.Y),
            math.min(viewport.X, pos.X + size.X), math.min(viewport.Y, pos.Y + size.Y)
        node = object.Parent
        while node do
            if node:IsA("GuiObject") and node.ClipsDescendants then
                local p, s = node.AbsolutePosition, node.AbsoluteSize
                left, top = math.max(left, p.X), math.max(top, p.Y)
                right, bottom = math.min(right, p.X + s.X), math.min(bottom, p.Y + s.Y)
            end
            node = node.Parent
        end
        return right > left and bottom > top
    end

    function Q.path(object)
        local parts, node = {}, object
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        for _ = 1, 8 do
            if not node or node == playerGui then break end
            parts[#parts + 1] = Q.normalize(node.Name)
            node = node.Parent
        end
        return table.concat(parts, " ")
    end

    function Q.isDialogPath(path)
        return path:find("dialog", 1, true) or path:find("choice", 1, true)
            or path:find("notification", 1, true) or path:find("toast", 1, true)
            or path:find("reward", 1, true) or path:find("health", 1, true)
    end

    function Q.fieldRole(field)
        local key = Q.normalize(field):gsub('[^%w]', '')
        for _, prefix in ipairs({'currentquest', 'activequest', 'quest', 'mission', 'objective'}) do
            if key:sub(1, #prefix) == prefix then key = key:sub(#prefix + 1); break end
        end
        local roles = {
            npc='target', npcname='target', mob='target', mobname='target', enemy='target',
            enemyname='target', target='target', targetname='target', alvo='target', inimigo='target',
            current='current', kills='current', killed='current', killcount='current', currentkills='current',
            defeated='current', progress='current', progresscurrent='current', amountkilled='current', abates='current',
            required='required', requiredkills='required', killsrequired='required', total='required', totalrequired='required',
            amount='required', goal='required', needed='required', killsneeded='required', maxkills='required',
            quantidade='required', active='active', isactive='active', enabled='active', completed='complete', complete='complete',
        }
        return roles[key]
    end

    function Q.readObjective()
        local groups = {}
        for index, item in ipairs(Q.texts) do
            local node = item.object
            if not item.notice and not Q.isDialogPath(item.path or Q.path(node)) then
                item.order = index
                for _ = 1, 12 do
                    if not node or node:IsA('PlayerGui') then break end
                    if node:IsA('ScreenGui') and not Q.hasQuestCue(node.Name) then break end
                    local group = groups[node]
                    if not group then group = {}; groups[node] = group end
                    group[#group + 1] = item
                    if node:IsA('ScreenGui') then break end
                    node = node.Parent
                end
            end
        end
        local best, bestScore
        for panel, items in pairs(groups) do
            if #items <= 64 then
                table.sort(items, function(a, b)
                    local pa, pb = a.object.AbsolutePosition, b.object.AbsolutePosition
                    local rowA, rowB = math.floor(pa.Y / 4), math.floor(pb.Y / 4)
                    if rowA ~= rowB then return rowA < rowB end
                    if pa.X ~= pb.X then return pa.X < pb.X end
                    return a.order < b.order
                end)
                local questPanel = Q.hasQuestCue(Q.path(panel)) ~= nil
                local verbCue, completeCue, invalid = false, false, false
                local parts = {}
                for _, item in ipairs(items) do
                    verbCue = verbCue or Q.verbTail(item.text) ~= nil
                    local caption = item.text:gsub('[%p]+$', '')
                    if Q.hasQuestCue(caption) then questPanel = true end
                    completeCue = completeCue or caption == 'completed' or caption == 'quest complete' or caption == 'quest completed'
                    if item.text:find('would you', 1, true) or item.text:find('do you want', 1, true)
                        or caption == 'sure' or caption == 'accept quest' then invalid = true end
                    parts[#parts + 1] = item.text
                end
                local target, strength, explicit, targetCurrent, targetRequired, targetRatio
                local current, required, ratio, fieldCurrent, fieldRequired
                local candidates = {}
                for _, item in ipairs(items) do
                    local field, value = item.text:match('^(.-)%s*[:=]%s*(.+)$')
                    local role = Q.fieldRole(field or item.object.Name)
                    local number = tonumber(value or item.text)
                    if role == 'current' and number then fieldCurrent = number end
                    if role == 'required' and number then fieldRequired = number end
                    local c, r, actualRatio = Q.progress(item.text)
                    if r and (not required or (actualRatio and not ratio)) then current, required, ratio = c, r, actualRatio end
                    if not (number and (role == 'current' or role == 'required')) then
                        local name, isExplicit, weight = Q.targetPhrase(item.text, true, questPanel or verbCue)
                        if name then
                            if role == 'target' then weight = math.max(weight, 4) end
                            candidates[#candidates + 1] = {key = Q.key(name), weight = weight}
                            if not strength or weight > strength then
                                target, strength, explicit = name, weight, isExplicit or role == 'target'
                                targetCurrent, targetRequired, targetRatio = c, r, actualRatio
                            end
                        end
                    end
                end
                local combined = table.concat(parts, ' ')
                local joinedCurrent, joinedRequired, joinedRatio = Q.progress(combined)
                if joinedRequired and joinedRatio and not ratio then current, required, ratio = joinedCurrent, joinedRequired, true end
                if targetRequired and targetRatio then current, required, ratio = targetCurrent, targetRequired, true end
                if not ratio and fieldRequired and fieldRequired > 0 then current, required = fieldCurrent or 0, fieldRequired end
                local ambiguous = false
                for _, candidate in ipairs(candidates) do
                    if target and candidate.weight >= strength and candidate.key ~= Q.key(target) then ambiguous = true end
                end
                if not invalid and not ambiguous and target and ((explicit and (strength == 3 or questPanel or required)) or ((questPanel or verbCue) and required)) then
                    local score = strength * 35 + (required and (ratio and 90 or 35) or 0)
                        + (questPanel and 25 or 0) + (completeCue and 10 or 0)
                        + (Q.names[Q.key(target)] and 20 or 0) - #items / 10
                    if not bestScore or score > bestScore then
                        bestScore = score
                        best = {targetName = target, current = current, required = required,
                            complete = completeCue or (required ~= nil and current >= required),
                            panel = panel, rawText = combined, source = 'status'}
                    end
                end
            end
        end
        return best
    end

    function Q.readStatsObjective()
        local scopes, visited = {LocalPlayer}, {[LocalPlayer] = true}
        local function addScope(object)
            if object and object.Parent and not visited[object] then visited[object] = true; scopes[#scopes + 1] = object end
        end
        for object in pairs(World.stats) do
            if object.Parent and Q.hasQuestCue(object.Name) then addScope(object); addScope(object.Parent) end
        end
        local best
        for _, scope in ipairs(scopes) do
            local scoped = Q.hasQuestCue(scope.Name) ~= nil
            local values = {}
            local function add(field, value)
                if scoped or Q.hasQuestCue(field) then
                    local role = Q.fieldRole(field)
                    if role then values[role] = value end
                end
            end
            local ok, attrs = pcall(function() return scope:GetAttributes() end)
            if ok then for field, value in pairs(attrs) do add(field, value) end end
            for _, object in ipairs(scope:GetChildren()) do
                if object:IsA('ValueBase') then add(object.Name, object.Value) end
            end
            local target = type(values.target) == 'string' and Q.targetPhrase(values.target, true, true)
            local current, required = tonumber(values.current), tonumber(values.required)
            if type(values.current) == 'string' then
                local c, r = Q.progress(values.current)
                if r then current, required = c, r end
            end
            if values.active ~= false and target and required and required > 0 then
                local candidate = {targetName = target, current = current or 0, required = required,
                    complete = values.complete == true or (current or 0) >= required, source = 'stats', panel = scope}
                if not best or (current ~= nil and not best.measured) then candidate.measured = current ~= nil; best = candidate end
            end
        end
        return best
    end

    function Q.scanGui(now)
        Q.texts, Q.buttons, Q.notices = {}, {}, {}
        Q.textsByContainer, Q.textsByParent, Q.buttonCountByParent = {}, {}, {}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then Q.objective = nil; return end
        local seen = {}
        for object in pairs(World.gui) do
            if object:IsA("GuiObject") and Q.visible(object)
                and not object:FindFirstAncestorWhichIsA("BillboardGui")
                and not object:FindFirstAncestorWhichIsA("SurfaceGui") then
                if Q.isText(object) then
                    local text = Q.normalize(object.Text)
                    if text ~= "" then
                        local notice = text:match("started a new quest%s*:%s*(.+)$")
                        local completed = not object:IsA("GuiButton") and not text:find("?", 1, true)
                            and (text:find("quest completed", 1, true) or text:find("quest complete", 1, true)
                                or text:find("completed the quest", 1, true) or text:find("completed your quest", 1, true))
                        local path = Q.path(object)
                        if path:find("dialog", 1, true) or path:find("choice", 1, true) then completed = false end
                        local item = {object = object, text = text, notice = notice ~= nil, path = path}
                        Q.texts[#Q.texts + 1] = item
                        if notice or completed then
                            seen[object] = true
                            local previous = Q.seenNotices[object]
                            if not previous or previous.text ~= text then previous = {text = text, time = now}; Q.seenNotices[object] = previous end
                            Q.notices[#Q.notices + 1] = {name = notice, kind = notice and "started" or "completed", time = previous.time}
                        end
                    end
                end
                if object:IsA("GuiButton") then Q.buttons[#Q.buttons + 1] = object end
            end
        end
        local neededContainers, neededParents = {}, {}
        for _, button in ipairs(Q.buttons) do
            neededContainers[button] = true
            local parent = button.Parent
            if parent then
                Q.buttonCountByParent[parent] = (Q.buttonCountByParent[parent] or 0) + 1
                if button:IsA("ImageButton") then neededParents[parent] = true end
            end
            local node = parent
            for _ = 1, 4 do
                if not node or node:IsA("ScreenGui") then break end
                neededContainers[node] = true
                node = node.Parent
            end
        end
        for _, item in ipairs(Q.texts) do
            local object = item.object
            local parent = object.Parent
            if parent and neededParents[parent] then
                local siblings = Q.textsByParent[parent]
                if not siblings then siblings = {}; Q.textsByParent[parent] = siblings end
                siblings[#siblings + 1] = item
            end
            local node, depth = parent, 0
            while node and node ~= playerGui and depth < 12 do
                if neededContainers[node] then
                    local descendants = Q.textsByContainer[node]
                    if not descendants then descendants = {}; Q.textsByContainer[node] = descendants end
                    descendants[#descendants + 1] = item
                end
                node, depth = node.Parent, depth + 1
            end
        end
        for object in pairs(Q.seenNotices) do if not seen[object] then Q.seenNotices[object] = nil end end
        Q.objective = Q.readObjective() or Q.readStatsObjective()
        Q.nextGuiScan = now + 0.85
    end

    function Q.modelFor(object)
        local fallback
        while object and object ~= workspace do
            if object:IsA("Model") and not Players:GetPlayerFromCharacter(object) and object ~= LocalPlayer.Character then
                if getMobRoot(object) then
                    if getMobHumanoid(object) then return object end
                    fallback = fallback or object
                end
            end
            object = object.Parent
        end
        return fallback
    end

    function Q.addGiver(object, priority, found, originPosition)
        local billboard = object:FindFirstAncestorWhichIsA("BillboardGui")
        local model = Q.modelFor(billboard and billboard.Adornee or object)
        if not model or not model:IsDescendantOf(workspace) then return end
        local part = getMobRoot(model)
        if not part then return end
        if originPosition then
            local offset = part.Position - originPosition
            if offset:Dot(offset) > Q.searchRadiusSquared then return end
        end
        found[model] = math.max(found[model] or 0, priority)
    end

    function Q.worldPartForText(object, billboard)
        local adornee = billboard and billboard.Adornee
        if adornee then
            if adornee:IsA("BasePart") then return adornee end
            if adornee:IsA("Model") then return getMobRoot(adornee) end
        end
        local node = object
        while node and node ~= workspace do
            if node:IsA("BasePart") then return node end
            if node:IsA("Model") then
                local part = getMobRoot(node)
                if part then return part end
            end
            node = node.Parent
        end
        return nil
    end

    function Q.addMobAlias(aliases, value)
        if type(value) ~= 'string' or value == '' or Q.hasQuestCue(value) then return end
        local _, _, ratio = Q.progress(value)
        if ratio then return end
        local text = Q.targetPhrase(value, true, true)
        if not text then return end
        local key = Q.key(text)
        if key == '' or key == 'model' or key == 'character' or key:match('^damage%s') then return end
        aliases[key] = text
    end

    function Q.collectMobAliases(model)
        local aliases = {}
        local normalizedName = Q.normalize(model.Name)
        Q.addMobAlias(aliases, model.Name)
        for _, prefix in ipairs({'npc_', 'mob_', 'enemy_', 'npc-', 'mob-', 'enemy-'}) do
            if normalizedName:sub(1, #prefix) == prefix then Q.addMobAlias(aliases, model.Name:sub(#prefix + 1)) end
        end
        local humanoid = getMobHumanoid(model)
        if humanoid then Q.addMobAlias(aliases, humanoid.DisplayName) end
        local ok, attrs = pcall(function() return model:GetAttributes() end)
        if ok then
            for field, value in pairs(attrs) do
                local key = Q.normalize(field):gsub('[^%w]', '')
                if Q.fieldRole(field) == 'target' or key == 'name' or key == 'displayname' or key == 'mobtype' or key == 'enemytype' then
                    Q.addMobAlias(aliases, value)
                end
            end
        end
        for _, object in ipairs(model:GetDescendants()) do
            if Q.isText(object) and (object:FindFirstAncestorWhichIsA('BillboardGui') or object:FindFirstAncestorWhichIsA('SurfaceGui')) then
                if not Q.path(object):find('health', 1, true) then Q.addMobAlias(aliases, object.Text) end
            elseif object:IsA('StringValue') then
                local key = Q.normalize(object.Name):gsub('[^%w]', '')
                if Q.fieldRole(object.Name) == 'target' or key == 'displayname' or key == 'mobtype' or key == 'enemytype' then Q.addMobAlias(aliases, object.Value) end
            end
        end
        return aliases
    end

    function Q.scanWorld(now)
        local _, originRoot = Motion.character()
        if not originRoot then
            Q.nextWorldScan = now + 1.5
            return
        end

        local originPosition = originRoot.Position
        local found, plates, eligible, visitedModels = {}, {}, {}, {}
        local knownGiver = Q.questGiver
        if not knownGiver or not knownGiver.Parent or not knownGiver:IsDescendantOf(workspace) then
            knownGiver = Q.giver
        end
        local knownGiverValid = knownGiver and knownGiver.Parent and knownGiver:IsDescendantOf(workspace)

        -- Depois que o NPC da quest já é conhecido, não varre os marcadores de NPC
        -- novamente a cada ciclo. Só procura um novo NPC quando não há um válido salvo.
        if knownGiverValid then
            -- Mantém o NPC já identificado fora da lista de mobs, mesmo que esteja além do raio.
            -- A escolha de um NPC novo continua limitada a 500 studs em Q.chooseGiver.
            found[knownGiver] = 100
        else
            -- A busca por NPCs que oferecem quests fica limitada a um raio de 500 studs.
            -- Textos da interface do jogador são ignorados; só objetos do mundo são avaliados.
            for object in pairs(World.texts) do
                if object.Parent and not Q.isOwnGui(object) and object:IsDescendantOf(workspace) then
                    local text = Q.normalize(object.Text)
                    local isNextQuest = text:find('next quest', 1, true) ~= nil
                    local isQuestLabel = text == 'quest' or text == 'quest giver'
                    local billboard = object:FindFirstAncestorWhichIsA('BillboardGui')
                    if billboard then
                        local part = Q.worldPartForText(object, billboard)
                        if part then
                            local offset = part.Position - originPosition
                            if offset:Dot(offset) <= Q.searchRadiusSquared then
                                plates[#plates + 1] = {object = object, billboard = billboard}
                                if (isNextQuest or isQuestLabel) and Q.visible(object, true) then
                                    Q.addGiver(object, isNextQuest and 100 or 20, found, originPosition)
                                end
                            end
                        end
                    elseif (isNextQuest or isQuestLabel) and Q.visible(object, true) then
                        Q.addGiver(object, isNextQuest and 100 or 20, found, originPosition)
                    end
                end
            end
            for prompt in pairs(World.prompts) do
                if prompt.Parent and prompt.Enabled
                    and Q.hasQuestCue(prompt.ActionText .. ' ' .. prompt.ObjectText .. ' ' .. prompt.Name) then
                    Q.addGiver(prompt, 20, found, originPosition)
                end
            end
        end

        Q.mobs, Q.givers = {}, {}
        Q.aliasExpires = Q.aliasExpires or setmetatable({}, {__mode = 'k'})
        for model, priority in pairs(found) do
            Q.givers[#Q.givers + 1] = {model = model, priority = priority}
        end

        -- Usa a consulta espacial do Roblox para obter candidatos próximos sem percorrer
        -- todos os Humanoids do mapa. Só faz a varredura global como fallback se a API falhar.
        local function addNearbyMob(model)
            if not model or visitedModels[model] then return end
            visitedModels[model] = true
            local modelRoot = getMobRoot(model)
            if not modelRoot then return end
            local offset = modelRoot.Position - originPosition
            if offset:Dot(offset) > Q.searchRadiusSquared then return end
            if not World.liveMob(model) or found[model] then return end

            Q.mobs[#Q.mobs + 1], eligible[model] = model, true
            if not Q.mobAliases[model] or now >= (Q.aliasExpires[model] or 0) then
                Q.mobAliases[model], Q.aliasExpires[model] = Q.collectMobAliases(model), now + 10 + math.random() * 6
            end
        end

        local queryOK, nearbyParts = pcall(function()
            return workspace:GetPartBoundsInRadius(originPosition, Q.searchRadius)
        end)
        if queryOK and type(nearbyParts) == 'table' then
            for _, part in ipairs(nearbyParts) do
                local node = part
                while node and node ~= workspace do
                    if node:IsA('Model') then
                        if visitedModels[node] then break end
                        if node:FindFirstChildOfClass('Humanoid') then
                            addNearbyMob(node)
                            break
                        end
                    end
                    node = node.Parent
                end
            end
        else
            for humanoid in pairs(World.humanoids) do
                local model = humanoid.Parent
                if model then addNearbyMob(model) end
            end
        end

        for _, plate in ipairs(plates) do
            local model = Q.modelFor(plate.billboard.Adornee or plate.object)
            if model and eligible[model] and not Q.path(plate.object):find('health', 1, true) then
                Q.addMobAlias(Q.mobAliases[model], plate.object.Text)
            end
        end
        for _, model in ipairs(Q.mobs) do
            for key, name in pairs(Q.mobAliases[model]) do Q.names[key] = name end
        end
        Q.nextWorldScan = now + 1.5
    end

    function Q.validMob(model, targetName)
        if not model or not model.Parent or not model:IsDescendantOf(workspace)
            or model == LocalPlayer.Character or Players:GetPlayerFromCharacter(model) then return false end
        local humanoid, root = getMobHumanoid(model), getMobRoot(model)
        if not humanoid or humanoid.Health <= 0 or not root then return false end
        local key = Q.key(targetName)
        local aliases = Q.mobAliases[model]
        if not aliases then aliases = Q.collectMobAliases(model); Q.mobAliases[model] = aliases end
        return key ~= '' and aliases[key] ~= nil
    end

    function Q.nearestMob(root, targetName)
        local best, bestDistanceSquared = nil, math.huge
        for _, model in ipairs(Q.mobs) do
            if Q.validMob(model, targetName) and os.clock() >= (Motion.blocked[model] or 0) then
                local part = getMobRoot(model)
                if part then
                    local offset = part.Position - root.Position
                    local distanceSquared = offset:Dot(offset)
                    if distanceSquared <= Q.searchRadiusSquared and distanceSquared < bestDistanceSquared then
                        best, bestDistanceSquared = model, distanceSquared
                    end
                end
            end
        end
        return best
    end

    function Q.chooseGiver(root)
        local function withinSearchRadius(model)
            local part = model and model.Parent and getMobRoot(model)
            if not part then return nil end
            local offset = part.Position - root.Position
            local distanceSquared = offset:Dot(offset)
            if distanceSquared <= Q.searchRadiusSquared then return part, distanceSquared end
            return nil
        end

        if Q.repeatEnabled and Q.lastGiver and Q.lastGiver.Parent
            and Q.lastGiver:IsDescendantOf(workspace) and withinSearchRadius(Q.lastGiver) then
            return Q.lastGiver
        end
        local best, bestPriority, bestDistanceSquared = nil, -1, math.huge
        for _, entry in ipairs(Q.givers) do
            local _, distanceSquared = withinSearchRadius(entry.model)
            if distanceSquared and (entry.priority > bestPriority
                or (entry.priority == bestPriority and distanceSquared < bestDistanceSquared)) then
                best, bestPriority, bestDistanceSquared = entry.model, entry.priority, distanceSquared
            end
        end
        return best
    end

    function Q.buttonLabel(button)
        local parts = {}
        if button:IsA("TextButton") and Q.normalize(button.Text) ~= "" then
            parts[#parts + 1] = Q.normalize(button.Text)
        end
        for _, item in ipairs(Q.textsByContainer[button] or {}) do
            if item.object ~= button then parts[#parts + 1] = item.text end
        end
        if #parts == 0 and button:IsA("ImageButton") then
            local p, size = button.AbsolutePosition, button.AbsoluteSize
            local count = Q.buttonCountByParent[button.Parent] or 0
            for _, item in ipairs(Q.textsByParent[button.Parent] or {}) do
                if not item.object:IsA("GuiButton") then
                    local center = item.object.AbsolutePosition + item.object.AbsoluteSize / 2
                    if count == 1 or (center.X >= p.X and center.X <= p.X + size.X
                        and center.Y >= p.Y and center.Y <= p.Y + size.Y) then
                        parts[#parts + 1] = item.text
                    end
                end
            end
        end
        return Q.normalize(table.concat(parts, " ")):gsub("[%p]+$", "")
    end

    function Q.findAction(allowGeneric)
        local actions = {sure = 100, yes = 80, accept = 95, ["accept quest"] = 100,
            ["take quest"] = 100, ["start quest"] = 100, ["repeat"] = 90,
            ["repeat quest"] = 95, again = 85, ["continue"] = 60,
            claim = 100, ["claim reward"] = 100, ["turn in"] = 100,
            complete = 95, ["complete quest"] = 100, finish = 90,
            sim = 80, aceitar = 95, repetir = 90, continuar = 60, concluir = 95}
        local best, bestScore
        for _, button in ipairs(Q.buttons) do
            local label = Q.buttonLabel(button)
            local name = Q.normalize(button.Name):gsub("button$", ""):gsub("[%p]+$", "")
            local score = actions[label] or (label == "" and actions[name])
            if score and os.clock() >= (Q.buttonCooldowns[button] or 0) then
                local context, node = Q.path(button), button.Parent
                for _ = 1, 4 do
                    if not node or node:IsA("ScreenGui") then break end
                    for _, item in ipairs(Q.textsByContainer[node] or {}) do
                        context = context .. " " .. item.text
                    end
                    if Q.hasQuestCue(context) then break end
                    node = node.Parent
                end
                if Q.hasQuestCue(context) or allowGeneric then
                    if Q.repeatEnabled and (label == "repeat" or label == "repeat quest" or label == "again") then score = score + 20 end
                    if not bestScore or score > bestScore then best, bestScore = button, score end
                end
            end
        end
        return best
    end

    -- Used only after a completion signal: prioritize turn-in/reward actions,
    -- then the repeat/confirmation action. No quest buttons are searched before completion.
    function Q.findRepeatStep()
        local priorities = {
            claim = 130, ["claim reward"] = 130, ["turn in"] = 130,
            ["coletar recompensa"] = 130, ["reivindicar recompensa"] = 130,
            ["entregar missao"] = 130, ["entregar missão"] = 130,
            complete = 125, ["complete quest"] = 125, finish = 125,
            concluir = 125, ["concluir missao"] = 125, ["concluir missão"] = 125,
            ["repeat"] = 120, ["repeat quest"] = 120, again = 120,
            repetir = 120, ["repetir quest"] = 120, ["repetir missao"] = 120,
            ["repetir missão"] = 120, ["repetir a missao"] = 120, ["repetir a missão"] = 120,
            sure = 110, yes = 110, accept = 110, ["accept quest"] = 110,
            ["take quest"] = 110, ["start quest"] = 110, sim = 110, aceitar = 110,
            ["aceitar missao"] = 110, ["aceitar missão"] = 110,
            ["continue"] = 105, continuar = 105,
        }
        local best, bestScore
        for _, button in ipairs(Q.buttons) do
            local label = Q.buttonLabel(button)
            local name = Q.normalize(button.Name):gsub("button$", ""):gsub("[%p]+$", "")
            local score = priorities[label] or (label == "" and priorities[name])
            if score and os.clock() >= (Q.buttonCooldowns[button] or 0) then
                local context, node = Q.path(button), button.Parent
                for _ = 1, 4 do
                    if not node or node:IsA("ScreenGui") then break end
                    for _, item in ipairs(Q.textsByContainer[node] or {}) do
                        context = context .. " " .. item.text
                    end
                    if Q.hasQuestCue(context) then break end
                    node = node.Parent
                end
                local path = Q.normalize(Q.path(button))
                local inQuestContext = Q.hasQuestCue(context)
                    or path:find("dialog", 1, true) ~= nil
                    or path:find("choice", 1, true) ~= nil
                if inQuestContext and (not bestScore or score > bestScore) then
                    best, bestScore = button, score
                end
            end
        end
        return best
    end

    function Q.releaseInputs()
        if Q.ownsInput then QuestRuntime.Interacting = false; Q.ownsInput = false end
        local point = Q.mouseDown
        if point then
            pcall(function() VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0) end)
            pcall(function() VirtualUser:Button1Up(point, workspace.CurrentCamera.CFrame) end)
        end
        Q.mouseDown = nil
        if QuestRuntime.ReleaseAttack then pcall(QuestRuntime.ReleaseAttack) end
        if Q.heldPrompt then pcall(function() Q.heldPrompt:InputHoldEnd() end); Q.heldPrompt = nil end
        if Q.hiddenHub then
            pcall(function() ScreenGui.Enabled = not destroyed and uiOpen end)
            Q.hiddenHub = false
        end
    end

    function Q.clickAt(point, token)
        if destroyed or token ~= Q.generation or QuestRuntime.Interacting or QuestRuntime.ItemBusy or QuestRuntime.FruitBuying then return false end
        Q.ownsInput, QuestRuntime.Interacting = true, true
        local wasEnabled = ScreenGui.Enabled
        if wasEnabled then Q.hiddenHub = true; ScreenGui.Enabled = false; task.wait(0.04) end
        local ok, clicked = pcall(function()
            if destroyed or token ~= Q.generation then return false end
            Q.mouseDown = point
            local down = pcall(function()
                VirtualInputManager:SendMouseMoveEvent(point.X, point.Y, game)
                VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
            end)
            if down then task.wait(0.06); return true end
            local fallback = pcall(function() VirtualUser:CaptureController(); VirtualUser:Button1Down(point, workspace.CurrentCamera.CFrame) end)
            if fallback then task.wait(0.06) end
            return fallback
        end)
        Q.releaseInputs()
        return ok and clicked == true
    end

    function Q.clickButton(button)
        if not Q.visible(button) then return false end
        local strategy = Q.attempts % 3
        if strategy ~= 0 then
            local signal = strategy == 1 and button.Activated or button.MouseButton1Click
            if World.emit(signal, nil, 1) then return true end
        end
        return Q.clickAt(button.AbsolutePosition + button.AbsoluteSize / 2, Q.generation)
    end

    function Q.moveNear(character, root, model, spacing)
        if LocalPlayer.Character ~= character or not root or not getMobRoot(model) then return false end
        return Motion.request("Quest", model, spacing, Q.phase == "FARM" and "mob" or "giver")
    end

    function Q.interact(model)
        local token = Q.generation
        local interactables = {}
        if Q.attempts % 3 ~= 2 then
            local now = os.clock()
            local cached = Q.interactableCache[model]
            if cached and cached.expires > now then
                interactables = cached.items
            else
                local found = {}
                for _, object in ipairs(model:GetDescendants()) do
                    if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
                        found[#found + 1] = object
                    end
                end
                Q.interactableCache[model] = {items = found, expires = now + 3}
                interactables = found
            end
        end
        for _, object in ipairs(interactables) do
            if object.Parent and object:IsDescendantOf(model) and object:IsA("ProximityPrompt") and object.Enabled then
                if type(fireproximityprompt) == "function" then
                    local ok = pcall(fireproximityprompt, object)
                    if ok then return true end
                end
                local ok = pcall(function()
                    Q.heldPrompt = object
                    object:InputHoldBegin()
                    local finish = os.clock() + math.min(object.HoldDuration + 0.1, 8)
                    repeat task.wait(0.05) until os.clock() >= finish or destroyed or token ~= Q.generation
                    object:InputHoldEnd()
                    Q.heldPrompt = nil
                end)
                Q.releaseInputs()
                if ok then return true end
            elseif object.Parent and object:IsDescendantOf(model) and object:IsA("ClickDetector") and type(fireclickdetector) == "function" then
                local ok = pcall(fireclickdetector, object)
                if ok then return true end
            end
        end
        local part = model:FindFirstChild("Head") or getMobRoot(model)
        local camera = workspace.CurrentCamera
        if not part or not camera then return false end
        local point, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
            task.wait(0.1)
            point, onScreen = camera:WorldToViewportPoint(part.Position)
        end
        if onScreen and point.Z > 0 then return Q.clickAt(Vector2.new(point.X, point.Y), token) end
        return false
    end

    function Q.changePhase(phase, now)
        Q.phase, Q.phaseAt, Q.nextAction, Q.attempts = phase, now, 0, 0
        Q.target = nil
        QuestRuntime.Farming = false
        Motion.release("Quest")
    end

    function Q.startFarm(targetName, now, root, fromToast)
        local starting = Q.phase ~= "FARM"
        local changed = Q.key(targetName) ~= Q.key(Q.targetName)
        if starting then
            Q.questGiver = Q.giver or Q.chooseGiver(root)
            Q.returnCFrame = root.CFrame
            Q.questStartedAt = now
            Q.awaitingNewQuest, Q.completedAt, Q.completedCurrent = false, nil, nil
            Q.changePhase("FARM", now)
        end
        if starting or changed then
            Q.target, Q.progressSeen, Q.required, Q.pendingDeaths = nil, nil, nil, 0
        end
        Q.targetName, Q.lastObjectiveAt, Q.toastTarget = targetName, now, fromToast == true
        Q.lastGiver = Q.questGiver or Q.lastGiver
    end

    function Q.observeProgress(objective)
        if not objective or not objective.required then return end
        local current = objective.current
        if Q.progressSeen then
            if current < Q.progressSeen then Q.pendingDeaths = 0
            else
                local advance = current - Q.progressSeen
                Q.pendingDeaths = math.max(0, Q.pendingDeaths - advance)
            end
        end
        Q.progressSeen, Q.required = current, objective.required
    end

    function Q.finishQuest(now, root)
        if Q.awaitingNewQuest then return end
        Q.questGiver = Q.questGiver or Q.giver or Q.chooseGiver(root)
        Q.returnCFrame = Q.returnCFrame or root.CFrame
        Q.completedAt, Q.completedCurrent, Q.awaitingNewQuest = now, Q.progressSeen, true
        Q.changePhase("RETURN", now)
        Q.status("Quest concluida. Voltando ao NPC que passou a missao...")
    end

    function Q.returnToGiver(character, root, now)
        local giver = Q.questGiver
        local part = giver and giver.Parent and giver:IsDescendantOf(workspace) and getMobRoot(giver)
        local destination, requested
        if part then
            requested = Q.moveNear(character, root, giver, 3)
            destination = part.Position
        elseif Q.returnCFrame then
            destination = Q.returnCFrame.Position
            requested = Motion.request("Quest", nil, 0, "point", destination)
        else
            Q.questGiver = Q.chooseGiver(root)
            Q.status("Aguardando o NPC da quest.")
            return
        end
        if requested and (root.Position - destination).Magnitude <= 5 then
            Q.giver = part and giver or nil
            Q.changePhase("CLAIM", now)
            Q.status("Aguardando entrega / proxima missao...")
        end
    end

    function Q.reset(now)
        Q.generation = Q.generation + 1
        Q.releaseInputs()
        Q.changePhase("SEEK", now)
        Q.giver, Q.targetName, Q.interactedAt, Q.acceptedAt = nil, nil, nil, nil
        Q.objective, Q.nextGuiScan, Q.nextWorldScan, Q.lastObjectiveAt = nil, 0, 0, 0
        Q.toastTarget = false
        Q.questGiver, Q.returnCFrame, Q.questStartedAt = nil, nil, nil
        Q.progressSeen, Q.required, Q.pendingDeaths = nil, nil, 0
        Q.awaitingNewQuest, Q.completedAt, Q.completedCurrent = false, nil, nil
        Q.acceptConfirmedAt = nil
    end

    function Q.statusText(message)
        local objective = Q.objective
        local target = Q.targetName or (objective and objective.targetName)
        local current = Q.progressSeen or (objective and objective.current)
        local required = Q.required or (objective and objective.required)
        local count = "Abates: aguardando o contador da quest"
        if required and current ~= nil then
            count = "Abates: " .. current .. "/" .. required .. " | Faltam: " .. math.max(0, required - current)
        end
        return "NPC da quest: " .. tostring(target or "lendo o status...") .. "\n" .. count .. "\n" .. tostring(message)
    end

    -- Durante o uso conjunto, o Auto Repeat Quest detecta que o objetivo terminou,
    -- auxilia apenas na entrega/repeticao e deixa o Auto Quest controlar o NPC.
    -- Fora do modo conjunto, mantem o comportamento original de dialogos.
    function Q.tick(now)
        if QuestRuntime.FruitBuying or not Q.repeatEnabled then return end
        if World.characterUnavailable or now < Motion.manualUntil or not World.ready then return end
        if now >= Q.nextGuiScan then Q.scanGui(now) end

        if QuestRuntime.AcceptOnlyEnabled then
            -- O painel da missao ainda visivel no canto esquerdo significa que
            -- o jogador ja possui quest. Nao interrompa o Auto Farm nem mande
            -- o personagem de volta ao NPC, mesmo com contador 5/5.
            if QuestRuntime.QuestHudBlocking then
                QuestRuntime.QuestPriority = false
                QuestRuntime.RepeatAtQuestNpc = false
                return
            end
            if now >= (QuestRuntime.RepeatArmAt or 0) then
                local objective = Q.objective
                -- O contador da missao e a notificacao de conclusao sao os
                -- dois sinais independentes usados para reconhecer o fim.
                if objective and objective.required and objective.current
                    and objective.required > 0 and objective.current >= objective.required then
                    QuestRuntime.RepeatCompletionPending = true
                end
                for _, notice in ipairs(Q.notices or {}) do
                    if notice.kind == "completed" and notice.time >= (Q.repeatEnabledAt or 0)
                        and now - notice.time <= 9 then
                        QuestRuntime.RepeatCompletionPending = true
                        break
                    end
                end
            end
            if QuestRuntime.RepeatCompletionPending then
                QuestRuntime.QuestPriority = true
                if Motion.owner == "Farm" then Motion.release("Farm") end
                if QuestRuntime.RequestAcceptanceUpdate then
                    QuestRuntime.RequestAcceptanceUpdate()
                end
            end
            -- Nao concorrer com o clique humano do Auto Quest ou com os itens.
            if not QuestRuntime.RepeatCompletionPending or not QuestRuntime.RepeatAtQuestNpc
                or QuestRuntime.Interacting or QuestRuntime.ItemBusy or QuestRuntime.SkillBusy then return end
            if now < Q.nextAction then return end
            local button = Q.findRepeatStep()
            if button then
                local label = Q.buttonLabel(button)
                local name = Q.normalize(button.Name):gsub("button$", "")
                -- O Sure!/Accept pertence ao Auto Quest para evitar clique duplo.
                local completionChoices = {
                    claim=true, ["claim reward"]=true, ["turn in"]=true,
                    complete=true, ["complete quest"]=true, finish=true,
                    concluir=true, ["concluir missao"]=true, ["concluir missão"]=true,
                    ["entregar missao"]=true, ["entregar missão"]=true,
                    ["coletar recompensa"]=true,
                    -- Repetir/aceitar/Sure fica exclusivamente com Auto Quest.
                }
                if completionChoices[label] or (label == "" and completionChoices[name]) then
                    Q.attempts = Q.attempts + 1
                    if Q.clickButton(button) then
                        Q.buttonCooldowns[button] = now + 1.75
                    end
                end
            end
            Q.nextAction = now + 1.2
            return
        end

        QuestRuntime.Farming = false
        if now >= Q.nextAction then
            local button = Q.findAction(false)
            if button then
                Q.attempts = Q.attempts + 1
                Q.clickButton(button)
            end
            Q.nextAction = now + 1.2
        end
    end

    local page = Pages.AutoQuest
    createCombatToggle(page, "AutoRepeatQuestCard", "Auto Repeat Quest", 1, function(state)
        Q.repeatEnabled = state == true
        QuestRuntime.RepeatEnabled = Q.repeatEnabled
        QuestRuntime.RepeatCompletionPending = false
        QuestRuntime.RepeatAtQuestNpc = false
        local now = os.clock()
        Q.repeatEnabledAt = now
        Q.repeatLastCompletionNotice = now
        Q.repeatStateInitialized = false
        Q.repeatPending = false
        Q.repeatWaitingForNewQuest = false
        Q.repeatLastComplete = false
        Q.repeatLastObjectiveKey, Q.repeatLastProgress = nil, nil
        Q.repeatCompletionKey, Q.repeatCompletionProgress = nil, nil
        Q.repeatClickedAt, Q.repeatDetectedAt = nil, nil
        Q.nextAction, Q.nextGuiScan = 0, 0
        Q.restart()
        Q.status(state and "Auto Repeat Quest ativado." or "Auto Repeat Quest desligado.")
    end)
    local statusCard = createStyledCard(page, "AutoQuestStatusCard", 124, 99)
    statusCard.Visible = false
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "AutoQuestStatus"
    statusLabel.Size = UDim2.new(1, -28, 1, -20)
    statusLabel.Position = UDim2.fromOffset(14, 10)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Theme.Text
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextWrapped = true
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.Parent = statusCard
    function Q.status(message)
        if statusLabel.Parent then
            local text = Q.statusText(message)
            if statusLabel.Text ~= text then statusLabel.Text = text end
        end
    end
    Q.status("Auto Repeat Quest ativado para interagir com as opcoes da missao.")

    function Q.restart()
        Q.generation = Q.generation + 1
        Q.releaseInputs()
        if Q.worker then pcall(task.cancel, Q.worker); Q.worker = nil end
        if destroyed or not Q.repeatEnabled then return end
        local token = Q.generation
        Q.worker = task.spawn(function()
            while not destroyed and Q.generation == token and Q.repeatEnabled do
                local ok, err = pcall(Q.tick, os.clock())
                if not ok then
                    Q.releaseInputs()
                    Motion.release("Quest")
                    QuestRuntime.Farming = false
                    Q.status("Erro recuperavel: " .. tostring(err):sub(1, 160))
                    if os.clock() - Q.lastErrorAt > 8 then warn("[Random Hub | Auto Repeat Quest] " .. tostring(err)); Q.lastErrorAt = os.clock() end
                    Q.nextAction = os.clock() + 1
                    Q.nextWorldScan, Q.nextGuiScan = Q.nextAction, Q.nextAction
                end
                task.wait(0.25)
            end
        end)
    end
    QuestRuntime.CancelInteraction = function()
        Q.restart()
    end
    Stoppers.AutoRepeatQuest = function()
        Q.repeatEnabled, QuestRuntime.Farming = false, false
        QuestRuntime.RepeatEnabled = false
        QuestRuntime.RepeatCompletionPending = false
        QuestRuntime.RepeatAtQuestNpc = false
        Q.repeatPending, Q.repeatWaitingForNewQuest = false, false
        Q.restart()
    end
end)


local AcceptQuest = {
    enabled = false, phase = "OFF", generation = 0, selectedKey = nil,
    entries = {}, catalogDirty = true, sourcesDirty = true,
    sourceConnections = {}, catalogConnections = {}, pending = false,
    attempts = 0, sentButtons = {}, beforeButtons = {}, lastWarning = -math.huge,
}

runSection("QuestAcceptance", function()
    local A = AcceptQuest
    local PromptService = getServiceSafe("ProximityPromptService")

    function A.key(value)
        return (string.lower(tostring(value or "")):gsub("<[^>]*>", ""):gsub("[^%w]", ""))
    end

    function A.questCue(value)
        local text = A.key(value)
        return text:find("quest", 1, true) ~= nil or text:find("mission", 1, true) ~= nil
            or text:find("missao", 1, true) ~= nil
    end

    function A.excluded(value)
        local text = A.key(value)
        for _, hint in ipairs({"shop", "dealer", "merchant", "vendor", "history", "definition", "template", "rewardshop"}) do
            if text:find(hint, 1, true) then return true end
        end
        return false
    end

    function A.disconnect(list)
        for _, connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
        table.clear(list)
    end

    function A.listen(list, object, property, callback)
        local ok, signal = pcall(function() return object:GetPropertyChangedSignal(property) end)
        if ok then list[#list + 1] = signal:Connect(callback) end
    end

    function A.visible(object)
        if not object or not object.Parent or object:IsDescendantOf(ScreenGui) then return false end
        local node = object
        while node and node ~= game do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("LayerCollector") and not node.Enabled then return false end
            node = node.Parent
        end
        return true
    end

    A.catalogEntities, A.catalogBoards, A.catalogInteractions = {}, {}, {}
    A.knownEntries, A.catalogBindings, A.regionCooldowns = {}, {}, {}
    local CollectionService = getServiceSafe("CollectionService")
    local CoreMarkers = CoreGui or getServiceSafe("CoreGui")

    function A.markerBoard(object)
        if object:IsA("BillboardGui") or object:IsA("SurfaceGui") then return object end
        return object:FindFirstAncestorWhichIsA("BillboardGui") or object:FindFirstAncestorWhichIsA("SurfaceGui")
    end

    function A.markerText(value)
        return tostring(value or ""):gsub("<[bB][rR]%s*/?>", "\n"):gsub("<[^>]*>", "")
            :gsub("&nbsp;", " "):gsub("\194\160", " "):gsub("–", "-"):gsub("—", "-")
            :gsub("−", "-"):gsub("&amp;", "&"):match("^%s*(.-)%s*$")
    end

    function A.levelRange(value)
        local text = string.lower(A.markerText(value))
        local cue = text:find("level", 1, true) or text:find("lvl", 1, true)
            or text:match("%f[%a]lv[%s%.:]") or text:find("nivel", 1, true) or text:find("nível", 1, true)
        if not cue then return nil end
        text = text:gsub("levels?", " "):gsub("lvl", " "):gsub("%f[%a]lv%.?", " ")
            :gsub("nível", " "):gsub("nivel", " "):gsub("[%[%]%(%)%:]", " ")
            :gsub("%f[%a]to%f[%A]", "-"):gsub("%f[%a]até%f[%A]", "-")
        local first, last = text:match("(%d+)%s*[%-%~/]%s*(%d+)")
        first, last = tonumber(first), tonumber(last)
        if first and last and first <= last then return first, last end
    end

    function A.clickCue(value)
        local key = A.key(value)
        return key:find("interact", 1, true) ~= nil or key:find("interagir", 1, true) ~= nil
            or key == "click" or key == "clique" or key == "talk" or key == "conversar"
    end

    function A.questionCue(value)
        local text = A.markerText(value):gsub("%s", "")
        return text == "?" or text == "[?]" or text == "❓" or text == "❔"
    end

    function A.questMarker(value)
        local key = A.key(value)
        return key == "quest" or key == "quests" or key == "questgiver" or key == "nextquest"
            or key == "availablequest" or key == "questavailable" or key == "newquest"
            or key == "mission" or key == "missiongiver" or key == "missao"
    end

    function A.entityRoot(object)
        if not object or not object.Parent then return nil end
        if object:IsA("BasePart") then return object end
        for _, name in ipairs({"HumanoidRootPart", "RootPart", "Root", "Head", "Torso", "UpperTorso"}) do
            local root = object:FindFirstChild(name)
            if root and root:IsA("BasePart") then return root end
        end
        if object:IsA("Folder") then return object:FindFirstChildWhichIsA("BasePart") end
        if object:IsA("Model") then
            for _, child in ipairs(object:GetChildren()) do
                if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then return nil end
            end
        end
        return World.root(object)
    end

    function A.npcFor(object)
        if not object then return nil end
        local board = A.markerBoard(object)
        local node = board and (board.Adornee or board) or object
        local fallback, part
        while node and node ~= workspace and node ~= game do
            if node:IsA("Camera") or node:IsA("WorldModel") or node:IsA("Tool") then return nil end
            if node:IsA("BasePart") then part = part or node end
            if (node:IsA("Model") or node:IsA("Folder")) and node:IsDescendantOf(workspace) then
                if node == LocalPlayer.Character or (node:IsA("Model") and Players:GetPlayerFromCharacter(node)) then return nil end
                local key = A.key(node.Name)
                if key ~= "map" and key ~= "world" and key ~= "islands" and key ~= "npcs" and not World.islands[node] then
                    local head, root = node:FindFirstChild("Head"), node:FindFirstChild("HumanoidRootPart")
                    if node:FindFirstChildOfClass("Humanoid") or node:FindFirstChildOfClass("AnimationController")
                        or (head and head:IsA("BasePart") and root and root:IsA("BasePart")) then return node end
                    if node:IsA("Model") and A.entityRoot(node) then fallback = fallback or node end
                    if node:IsA("Folder") and ((head and head:IsA("BasePart")) or (root and root:IsA("BasePart"))) then fallback = fallback or node end
                end
            end
            node = node.Parent
        end
        return fallback or (part and part:IsDescendantOf(workspace) and part or nil)
    end

    function A.entryKey(model)
        A.modelKeys = A.modelKeys or setmetatable({}, {__mode = "k"})
        if A.modelKeys[model] then return A.modelKeys[model] end
        local root = A.entityRoot(model)
        if not root then return nil end
        local island, position = World.islandFor(model), root.Position
        local key = model.Name .. "|" .. (island and island.Name or (model.Parent and model.Parent.Name or ""))
            .. "|" .. math.floor(position.X / 4) .. ":" .. math.floor(position.Y / 4) .. ":" .. math.floor(position.Z / 4)
        A.modelKeys[model] = key
        return key
    end

    function A.catalogActive()
        return not destroyed and not A.stopping and (A.enabled or (Pages.AutoQuest and Pages.AutoQuest.Visible))
    end

    function A.dirtyCatalog()
        A.catalogDirty = true
        if A.enabled then A.schedule(0.35) end
        if A.requestCatalog then A.requestCatalog() end
    end

    function A.trackCatalog(object, removed)
        if not object or object:IsDescendantOf(ScreenGui) or object:FindFirstAncestor("FlyToggle") then return end
        local relevant = false
        if object:IsDescendantOf(workspace) and (object:IsA("Model") or object:IsA("Folder")) then
            local rig = object:FindFirstChildOfClass("Humanoid") or object:FindFirstChildOfClass("AnimationController")
                or object:FindFirstChild("Head") or object:FindFirstChild("HumanoidRootPart")
            local metadata = A.metadata(object)
            if rig or metadata.quest then A.catalogEntities[object] = not removed or nil; relevant = true end
        elseif object:IsA("Humanoid") or object:IsA("AnimationController") then
            if object.Parent and object.Parent:IsDescendantOf(workspace) then A.catalogEntities[object.Parent] = true; relevant = true end
        elseif object:IsA("BasePart") and (object.Name == "Head" or object.Name == "HumanoidRootPart" or object.Name == "Root" or object.Name == "RootPart") then
            local model = A.npcFor(object)
            if model then A.catalogEntities[model] = true; relevant = true end
        elseif object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
            if object:IsDescendantOf(workspace) then A.catalogInteractions[object] = not removed or nil; relevant = true end
        end
        local board
        if object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("GuiObject") then board = A.markerBoard(object) end
        if board then
            if removed and object == board then A.catalogBoards[board] = nil else A.catalogBoards[board] = true end
            relevant = true
        end
        if object:IsA("ValueBase") and A.questCue(object.Name) then
            local model = A.npcFor(object)
            if model then A.catalogEntities[model] = true end
            relevant = true
        end
        if removed then
            A.catalogEntities[object], A.catalogInteractions[object] = nil, nil
            local bindings = A.catalogBindings[object]
            if bindings then
                for _, binding in pairs(bindings) do binding.connection:Disconnect() end
                A.catalogBindings[object] = nil
            end
        end
        if relevant then A.dirtyCatalog() end
    end

    function A.markerName(group)
        local best, score = nil, -math.huge
        local function consider(value, field, extra)
            for line in A.markerText(value):gmatch("[^\r\n]+") do
                local text = line:match("^%s*(.-)%s*$")
                if A.levelRange(text) then
                    text = text:match("^(.-)%s+[Ll][Ee][Vv][Ee][Ll]") or ""
                end
                local key = A.key(text)
                if text ~= "" and #text <= 64 and text:find("%a") and not text:find("%d+%s*/%s*%d+")
                    and not A.levelRange(text) and not A.clickCue(text) and not A.questionCue(text)
                    and not A.questMarker(text) and not A.excluded(text) and key ~= "level" and key ~= "fruitstock"
                    and (not text:find("%d") or field:find("name", 1, true)) then
                    local weight = extra or 0
                    if field:find("name", 1, true) then weight = weight + 100 end
                    if field:find("title", 1, true) then weight = weight + 50 end
                    if key == A.key(group.model.Name) then weight = weight + 20 end
                    if weight > score then best, score = text, weight end
                end
            end
        end
        for _, label in ipairs(group.labels) do consider(label.Text, A.key(label.Name), 0) end
        if not best then
            local humanoid = group.model:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.DisplayName ~= "" and humanoid.DisplayName ~= "Humanoid" then consider(humanoid.DisplayName, "name", -20) end
            if not best then consider(group.model.Name, "name", -50) end
        end
        return best or group.model.Name
    end

    function A.metadata(model, watch)
        local evidence = {quest=false, shop=false, enemy=false, npc=false}
        local questFields = {questgiver=true,isquestgiver=true,questnpc=true,isquestnpc=true,givesquests=true,givesquest=true,
            providesquest=true,providesquests=true,questid=true,questname=true,missionid=true,missiongiver=true}
        local enemyFields = {ismob=true,isenemy=true,isboss=true,hostile=true,mobtype=true,enemytype=true}
        local function positive(value)
            if type(value) == "boolean" then return value end
            if type(value) == "number" then return value > 0 end
            if typeof(value) == "Instance" then return value.Parent ~= nil end
            local key = A.key(value)
            return key ~= "" and key ~= "false" and key ~= "none" and key ~= "nil" and key ~= "0"
        end
        local function field(name, value)
            local key = A.key(name)
            if questFields[key] and positive(value) then evidence.quest = true end
            if enemyFields[key] and positive(value) then evidence.enemy = true end
            if key == "isnpc" and positive(value) then evidence.npc = true end
            if key == "npctype" or key == "role" or key == "interactiontype" then
                local role = A.key(value)
                if A.questMarker(role) or role == "questnpc" then evidence.quest = true end
                if A.excluded(role) or role == "fruitstock" or role == "shopkeeper" then evidence.shop = true end
                if role == "enemy" or role == "mob" or role == "boss" then evidence.enemy = true end
            end
        end
        local ok, attributes = pcall(function() return model:GetAttributes() end)
        if ok then for name, value in pairs(attributes) do field(name, value) end end
        if CollectionService then
            local tagsOk, tags = pcall(function() return CollectionService:GetTags(model) end)
            if tagsOk then
                for _, tag in ipairs(tags) do
                    local key = A.key(tag)
                    if questFields[key] or key == "quest" or key == "questgivers" then evidence.quest = true end
                    if enemyFields[key] or key == "enemy" or key == "mob" or key == "boss" then evidence.enemy = true end
                    if A.excluded(key) then evidence.shop = true end
                    if key == "npc" then evidence.npc = true end
                end
            end
        end
        for _, child in ipairs(model:GetChildren()) do
            local key = A.key(child.Name)
            if child:IsA("ValueBase") and (questFields[key] or enemyFields[key] or key == "npctype" or key == "role") then
                field(child.Name, child.Value)
                if watch then watch(child, "Value") end
            elseif child:IsA("Folder") and (key == "quest" or key == "questdata" or key == "questgiver") then
                for _, data in ipairs(child:GetChildren()) do
                    if data:IsA("ValueBase") then
                        local dataKey = A.key(data.Name)
                        field((dataKey == "id" or dataKey == "name") and ("Quest" .. data.Name) or data.Name, data.Value)
                        if watch then watch(data, "Value") end
                    end
                end
            end
        end
        local node = model
        for _ = 1, 10 do
            if not node or node == workspace then break end
            local key = A.key(node.Name)
            if key:find("questgiver", 1, true) or key:find("questnpc", 1, true)
                or key == "missiongivers" or key == "missionnpcs" then evidence.quest = true end
            if node == model and (A.excluded(node.Name) or key == "fruitstock") then evidence.shop = true end
            if key == "enemies" or key == "mobs" or key == "bosses" or key == "monsters" then evidence.enemy = true end
            if key == "npcs" or key == "npc" then evidence.npc = true end
            node = node.Parent
        end
        return evidence
    end

    function A.entryLevels(model, low, high)
        if low and high then return low, high end
        local minimum = {minlevel=5,minimumlevel=5,requiredlevel=4,levelrequirement=4,questlevel=3,level=1}
        local maximum = {maxlevel=true,maximumlevel=true,maxquestlevel=true}
        local rank = low and 100 or 0
        local function read(name,value)
            local key = A.key(name)
            if minimum[key] then
                local number = tonumber(value)
                if number and number >= 0 and minimum[key] > rank then low,rank = number,minimum[key] end
            elseif maximum[key] then
                local number = tonumber(value)
                if number and number >= 0 then high = high or number end
            elseif key == "levelrange" or key == "questlevels" then
                local first,last = A.levelRange("Level " .. tostring(value))
                if first and rank < 6 then low,rank = first,6 end
                high = high or last
            end
        end
        local ok,attrs = pcall(function() return model:GetAttributes() end)
        if ok then for name,value in pairs(attrs) do read(name,value) end end
        for _,child in ipairs(model:GetChildren()) do
            if child:IsA("ValueBase") then read(child.Name,child.Value)
            elseif child:IsA("Folder") and A.questCue(child.Name) then
                for _,data in ipairs(child:GetChildren()) do if data:IsA("ValueBase") then read(data.Name,data.Value) end end
            end
        end
        if low and high and high < low then high = nil end
        return low,high
    end

    function A.displayName(entry)
        local label = entry.name
        local low,high = tonumber(entry.minLevel),tonumber(entry.maxLevel)
        if low and high and low ~= high then return label .. " [Lv. " .. low .. "-" .. high .. "]" end
        if low then return label .. " [Lv. " .. low .. "]" end
        if high then return label .. " [Max Lv. " .. high .. "]" end
        return label
    end

    function A.refreshCatalog()
        local now = os.clock()
        A.catalogRevision = (A.catalogRevision or 0) + 1
        local revision = A.catalogRevision
        local found, groups, boards = {}, {}, {}
        local function watch(object, property)
            local bindings = A.catalogBindings[object]
            if not bindings then bindings = {}; A.catalogBindings[object] = bindings end
            local binding = bindings[property]
            if not binding or not binding.connection.Connected then
                local ok, signal = pcall(function()
                    return property == "Attributes" and object.AttributeChanged or object:GetPropertyChangedSignal(property)
                end)
                if not ok or not signal then return end
                local callback = A.dirtyCatalog
                if property == "Attributes" then
                    callback = function(field)
                        local key = A.key(field)
                        if A.questCue(field) or key == "npctype" or key == "role" or key == "interactiontype"
                            or key == "isnpc" or key == "ismob" or key == "isenemy" or key == "isboss" then A.dirtyCatalog() end
                    end
                end
                binding = {connection = signal:Connect(callback)}
                bindings[property] = binding
            end
            binding.revision = revision
        end
        local function groupFor(object, direct)
            local model = A.npcFor(object)
            if not model or not model.Parent or not model:IsDescendantOf(workspace) or not A.entityRoot(model) then return nil end
            if model == LocalPlayer.Character or (model:IsA("Model") and Players:GetPlayerFromCharacter(model)) then return nil end
            if model:FindFirstAncestorWhichIsA("Tool") or model:FindFirstAncestorWhichIsA("WorldModel") then return nil end
            local group = groups[model]
            if not group then
                group = {model=model,labels={},boards={},prompts={},clicks={},guiButtons={},promptSet={},clickSet={}}
                groups[model] = group
            end
            return group
        end
        for text in pairs(World.texts) do
            if text.Parent then local board = A.markerBoard(text); if board then boards[board] = true end end
        end
        for board in pairs(A.catalogBoards) do
            if board.Parent then boards[board] = true else A.catalogBoards[board] = nil end
        end
        for humanoid in pairs(World.humanoids) do if humanoid.Parent then groupFor(humanoid.Parent, true) end end
        for model in pairs(A.catalogEntities) do
            if not model.Parent then A.catalogEntities[model] = nil
            elseif model:IsDescendantOf(workspace) then groupFor(model, true) end
        end
        for board in pairs(boards) do
            watch(board, "Adornee"); watch(board, "Name")
            local group = groupFor(board)
            if group then group.boards[board] = true end
            for _, object in ipairs(board:GetDescendants()) do
                if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                    local raw, field = A.markerText(object.Text), A.key(object.Name)
                    local health = field:find("health", 1, true) or field == "hp" or raw:match("^%s*%d+%s*/%s*%d+%s*$")
                    if not health then watch(object, "Text"); watch(object, "Name") end
                    if group then
                        group.labels[#group.labels + 1] = object
                        local low, high = A.levelRange(raw)
                        if low then group.low, group.high = low, high end
                        group.interact = group.interact or A.clickCue(raw)
                        group.question = group.question or A.questionCue(raw)
                        group.quest = group.quest or A.questMarker(raw)
                        group.health = group.health or health
                        group.shop = group.shop or A.excluded(raw) or A.key(raw) == "fruitstock" or raw == "$"
                    end
                elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                    watch(object, "Name")
                    local field = A.key(object.Name)
                    if group and (field:find("quest", 1, true) or field:find("question", 1, true)) then group.question = true end
                end
                if group and object:IsA("GuiButton") then group.guiButtons[#group.guiButtons + 1] = object end
            end
        end
        local function interaction(object)
            if not object.Parent then return end
            local group = groupFor(object)
            if not group then return end
            if object:IsA("ProximityPrompt") then
                if not group.promptSet[object] then group.promptSet[object] = true; group.prompts[#group.prompts + 1] = object end
                watch(object, "ActionText"); watch(object, "ObjectText"); watch(object, "Enabled")
                if A.questMarker(object.ActionText) or A.questMarker(object.ObjectText)
                    or A.questCue(object.ActionText) and not A.excluded(object.ActionText) then group.quest = true end
                group.shop = group.shop or A.excluded(object.ActionText .. " " .. object.ObjectText)
            elseif object:IsA("ClickDetector") and not group.clickSet[object] then
                group.clickSet[object] = true; group.clicks[#group.clicks + 1] = object
            end
        end
        for prompt in pairs(World.prompts) do interaction(prompt) end
        for object in pairs(A.catalogInteractions) do
            if object.Parent then interaction(object) else A.catalogInteractions[object] = nil end
        end
        for model, group in pairs(groups) do
            local metadata = A.metadata(model, watch)
            local interested = metadata.quest or metadata.npc or group.quest or group.question or group.low or #group.labels > 0
            watch(model, "Attributes")
            if interested then watch(model, "Name") end
            if not group.low and #group.labels > 1 then
                local text = {}
                for _, label in ipairs(group.labels) do text[#text + 1] = A.markerText(label.Text) end
                local joined = table.concat(text, " ")
                group.low, group.high = A.levelRange(joined)
            end
            local actionable = group.interact or #group.prompts > 0 or #group.clicks > 0 or #group.guiButtons > 0 or metadata.npc
            local proven = metadata.quest or group.quest or group.question or (group.low and actionable)
            if proven and not metadata.enemy and not metadata.shop and not group.shop and not (group.health and not metadata.quest and not group.quest) then
                local root, name = A.entityRoot(model), A.markerName(group)
                local key = A.entryKey(model)
                if key and root and name and not A.excluded(name) then
                    for oldKey, old in pairs(A.knownEntries) do
                        if old.name == name and old.modelName == model.Name and old.position
                            and (not old.model or not old.model.Parent or not old.model:IsDescendantOf(workspace))
                            and (old.position - root.Position).Magnitude < 5 then key = oldKey; A.modelKeys[model] = key; break end
                    end
                    local island = World.islandFor(model)
                    group.low,group.high = A.entryLevels(model,group.low,group.high)
                    local entry = {key=key,model=model,modelName=model.Name,name=name,markers=group.labels,prompts=group.prompts,
                        clicks=group.clicks,guiButtons=group.guiButtons,minLevel=group.low,maxLevel=group.high,
                        position=root.Position,islandName=island and island.Name,seenAt=now}
                    found[key], A.knownEntries[key] = entry, entry
                end
            end
        end
        for key, entry in pairs(A.knownEntries) do
            if not found[key] then
                local loaded = entry.model and entry.model.Parent and entry.model:IsDescendantOf(workspace)
                if workspace.StreamingEnabled and not loaded and now - entry.seenAt < 300 then found[key] = entry
                else A.knownEntries[key] = nil end
            end
        end
        A.catalogConnections = {}
        for object, bindings in pairs(A.catalogBindings) do
            for property, binding in pairs(bindings) do
                if binding.revision ~= revision or not object.Parent then binding.connection:Disconnect(); bindings[property] = nil
                else A.catalogConnections[#A.catalogConnections + 1] = binding.connection end
            end
            if not next(bindings) then A.catalogBindings[object] = nil end
        end
        A.entries, A.catalogDirty, A.nextCatalogAt = found, false, now + 1
        if A.refreshDropdown then A.refreshDropdown() end
    end

    function A.stopDiscovery()
        A.discoveryGeneration = (A.discoveryGeneration or 0) + 1
        if A.discoveryWorker then pcall(task.cancel, A.discoveryWorker); A.discoveryWorker = nil end
        if A.coreAdded then A.coreAdded:Disconnect(); A.coreAdded = nil end
        if A.coreRemoved then A.coreRemoved:Disconnect(); A.coreRemoved = nil end
        if A.catalogTimer then pcall(task.cancel, A.catalogTimer); A.catalogTimer = nil end
        A.disconnect(A.catalogConnections)
        A.catalogBindings = {}
    end

    function A.startDiscovery()
        if A.discoveryWorker or A.discoveryStarting or not A.catalogActive() then return end
        A.discoveryStarting = true
        A.discoveryGeneration = (A.discoveryGeneration or 0) + 1
        local token = A.discoveryGeneration
        if CoreMarkers and not A.coreAdded then
            local ok, added, removed = pcall(function() return CoreMarkers.DescendantAdded, CoreMarkers.DescendantRemoving end)
            if ok then
                A.coreAdded = added:Connect(function(object) A.trackCatalog(object, false) end)
                A.coreRemoved = removed:Connect(function(object) A.trackCatalog(object, true) end)
            end
        end
        A.discoveryWorker = task.spawn(function()
            local scopes = {workspace}
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then scopes[#scopes + 1] = playerGui end
            if CoreMarkers then scopes[#scopes + 1] = CoreMarkers end
            local stack, visited = {}, 0
            for _, scope in ipairs(scopes) do
                local ok, children = pcall(function() return scope:GetChildren() end)
                if ok then for _, object in ipairs(children) do stack[#stack + 1] = object end end
            end
            while #stack > 0 do
                if token ~= A.discoveryGeneration or not A.catalogActive() then return end
                local object = table.remove(stack)
                if object.Parent and object ~= ScreenGui and object.Name ~= "FlyToggle" then
                    A.trackCatalog(object, false)
                    local ok, children = pcall(function() return object:GetChildren() end)
                    if ok then for _, child in ipairs(children) do stack[#stack + 1] = child end end
                end
                visited = visited + 1
                if visited % 160 == 0 then task.wait(0.03) end
            end
            A.dirtyCatalog()
            local nextAudit = os.clock() + 5
            while token == A.discoveryGeneration and A.catalogActive() do
                local now = os.clock()
                if now >= nextAudit then
                    A.dirtyCatalog()
                    nextAudit = now + (next(A.entries) and 12 or 5)
                end
                if workspace.StreamingEnabled and now >= (A.nextRegionAt or 0) and not Motion.streamPending and not Motion.owner
                    and not Motion.manualThread and not World.fruitScanActive and not World.farmSearchActive and not QuestRuntime.ItemBusy
                    and not QuestRuntime.Interacting and now >= Motion.manualUntil
                    and type(LocalPlayer.RequestStreamAroundAsync) == "function" then
                    local points = {}
                    local selected = A.selectedKey and A.knownEntries[A.selectedKey]
                    if selected and selected.position and (not selected.model or not selected.model.Parent or not selected.model:IsDescendantOf(workspace)) then
                        points[#points + 1] = {position=selected.position,key="selected:" .. selected.key}
                    end
                    for _, point in ipairs(World.travelPoints or {}) do points[#points + 1] = {position=point.position,key=point.name} end
                    for island in pairs(World.islands) do
                        local position = World.islandPosition(island)
                        if position and #points < 64 then points[#points + 1] = {position=position,key="island:" .. island:GetFullName()} end
                    end
                    A.nextRegionAt = now + 6
                    for _, point in ipairs(points) do
                        if point.position and now >= (A.regionCooldowns[point.key] or 0) then
                            A.regionCooldowns[point.key] = now + 75
                            pcall(function() LocalPlayer:RequestStreamAroundAsync(point.position, 1.5) end)
                            if token ~= A.discoveryGeneration or not A.catalogActive() then return end
                            A.dirtyCatalog()
                            break
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
        A.discoveryStarting = false
    end

    function A.selected()
        local entry = A.selectedKey and A.entries[A.selectedKey]
        if not entry or not entry.model.Parent or not entry.model:IsDescendantOf(workspace) then return nil end
        if A.excluded(entry.model.Name) then return nil end
        return entry
    end

    function A.role(name, scoped)
        local field = A.key(name)
        if not scoped and not A.questCue(field) then return nil end
        if field == "quest" or field == "currentquest" or field == "activequest" or field == "mission"
            or field == "currentmission" or field == "activemission" then return "identity" end
        for _, prefix in ipairs({"currentquest", "activequest", "quest", "currentmission", "mission"}) do
            if field:sub(1, #prefix) == prefix and #field > #prefix then field = field:sub(#prefix + 1); break end
        end
        if field == "active" or field == "isactive" or field == "hasquest" or field == "hasactivequest"
            or field == "inprogress" or field == "isrunning" then return "flag" end
        if field == "questid" or field == "missionid" or field == "questname" or field == "id" or field == "name" then return "identity" end
        if field == "status" or field == "state" then return "state" end
        if field == "completed" or field == "complete" or field == "cancelled" or field == "canceled" then return "ended" end
    end

    function A.valueActive(value)
        if typeof(value) == "Instance" then return value.Parent ~= nil end
        if type(value) == "boolean" then return value end
        if type(value) == "number" then return value > 0 end
        if type(value) ~= "string" then return nil end
        local key = A.key(value)
        local empty = {['']=true,none=true,nilvalue=true,['nil']=true,['false']=true,noquest=true,noactivequest=true,
            ['0']=true,idle=true,inactive=true,notactive=true,notstarted=true,completed=true,complete=true,
            finished=true,cancelled=true,canceled=true}
        return not empty[key]
    end

    function A.dataEligible(object)
        if object ~= LocalPlayer and not object:IsDescendantOf(LocalPlayer) then return false end
        local node = object
        while node and node ~= LocalPlayer do
            if node:IsA("PlayerGui") or node:IsA("PlayerScripts") or node:IsA("Backpack")
                or node:IsA("LuaSourceContainer") or A.excluded(node.Name) then return false end
            local key = A.key(node.Name)
            if key:find("reward", 1, true) or key:find("archive", 1, true) or key:find("catalog", 1, true)
                or key:find("availablequests", 1, true) then return false end
            node = node.Parent
        end
        return node == LocalPlayer
    end

    function A.stateScope(object)
        if not A.dataEligible(object) then return nil end
        local node, found = object, nil
        while node and node ~= LocalPlayer do
            if A.questCue(node.Name) then found = found or node end
            node = node.Parent
        end
        return found
    end

    function A.emptyQuestText(value)
        local key = A.key(value)
        return key == "noquest" or key == "noquests" or key == "noactivequest" or key == "noactivequests"
            or key == "nenhumamissaoativa" or key == "nenhumamissoativa" or key == "semmissao" or key == "semmisso"
            or key == "youdonthaveaquest" or key == "youhavenoquest" or key == "youhavenoactivequest"
    end

    function A.dialogName(value)
        local key = A.key(value)
        return key:find("dialog", 1, true) or key:find("conversation", 1, true) or key:find("choice", 1, true)
            or key == "talk" or key == "npctalk" or key == "npcinteraction"
    end

    function A.questPanel(object)
        if object:IsDescendantOf(ScreenGui) or object:FindFirstAncestorWhichIsA("BillboardGui")
            or object:FindFirstAncestorWhichIsA("SurfaceGui") then return nil end
        local text = (object:IsA("TextLabel") or object:IsA("TextButton")) and A.key(object.Text) or ""
        local title = text == "quest" or text == "currentquest" or text == "activequest" or A.emptyQuestText(text)
        local node, found = object.Parent, nil
        while node and not node:IsA("PlayerGui") do
            if node == ScreenGui or node:IsDescendantOf(ScreenGui) then return nil end
            local key = A.key(node.Name)
            if A.dialogName(node.Name) or key:find("notification", 1, true) or key:find("toast", 1, true)
                or key:find("questlist", 1, true) or key:find("questselect", 1, true) or A.excluded(node.Name) then return nil end
            if node:IsA("Frame") or node:IsA("ScrollingFrame") then
                if not found and (A.questCue(key) or title) then found = node end
            end
            node = node.Parent
        end
        if found then
            for button in pairs(World.gui) do
                if button.Parent and button:IsA("GuiButton") and button:IsDescendantOf(found)
                    and A.actionKind and A.actionKind(button) then return nil end
            end
        end
        return found
    end

    function A.stateChanged()
        if A.enabled then A.schedule(0.15) end
    end

    function A.refreshSources()
        A.disconnect(A.sourceConnections)
        A.sources, A.panels = {}, {}
        local scopes, watched = {[LocalPlayer]=false}, {}
        local function watch(object, property, callback)
            local properties = watched[object]
            if not properties then properties = {}; watched[object] = properties end
            if properties[property] then return end
            properties[property] = true
            A.listen(A.sourceConnections, object, property, callback or A.stateChanged)
        end
        for object in pairs(World.stats) do
            if object.Parent and A.dataEligible(object) then
                local scope = A.stateScope(object)
                if scope then scopes[scope] = true end
                if object:IsA("Folder") or object:IsA("Configuration") then
                    if scopes[object] == nil then scopes[object] = scope ~= nil end
                end
                local role = A.role(object.Name, scope ~= nil)
                if role and object:IsA("ValueBase") then
                    A.sources[#A.sources + 1] = {object=object,role=role}
                    watch(object, "Value")
                end
            end
        end
        for scope, scoped in pairs(scopes) do
            if scope.Parent then
                A.sourceConnections[#A.sourceConnections + 1] = scope.AttributeChanged:Connect(function(field)
                    if A.role(field, scoped) then
                        if scope:GetAttribute(field) == nil and A.acceptedLock and not World.characterUnavailable then
                            A.endedByRemoval = true
                        end
                        A.sourcesDirty = true; A.stateChanged()
                    end
                end)
                local ok, attrs = pcall(function() return scope:GetAttributes() end)
                if ok then
                    for field in pairs(attrs) do
                        local role = A.role(field, scoped)
                        if role then A.sources[#A.sources + 1] = {object=scope,attribute=field,role=role} end
                    end
                end
            end
        end
        for object in pairs(World.gui) do
            if object.Parent and (object:IsA("TextLabel") or object:IsA("TextButton")) then
                local panel = A.questPanel(object)
                if panel then A.panels[panel] = A.panels[panel] or {} end
            end
        end
        for panel, labels in pairs(A.panels) do
            watch(panel, "Visible")
            local parent = panel.Parent
            while parent and not parent:IsA("PlayerGui") do
                if parent:IsA("GuiObject") then watch(parent, "Visible")
                elseif parent:IsA("LayerCollector") then watch(parent, "Enabled") end
                parent = parent.Parent
            end
            for object in pairs(World.gui) do
                if object.Parent and object:IsA("TextLabel") and object:IsDescendantOf(panel) then
                    labels[#labels + 1] = object
                    watch(object, "Visible")
                    local present = A.key(object.Text) ~= "" and not A.emptyQuestText(object.Text)
                    watch(object, "Text", function()
                        local current = A.key(object.Text) ~= "" and not A.emptyQuestText(object.Text)
                        if current ~= present or A.emptyQuestText(object.Text) then present = current; A.stateChanged() end
                    end)
                end
            end
        end
        for object in pairs(World.gui) do
            if object.Parent and not object:IsDescendantOf(ScreenGui) then
                if object:IsA("GuiButton") and A.actionKind and A.actionKind(object) then
                    watch(object, "Visible")
                    local parent = object.Parent
                    for _ = 1, 8 do
                        if not parent or parent:IsA("PlayerGui") then break end
                        if parent:IsA("GuiObject") then watch(parent, "Visible")
                        elseif parent:IsA("LayerCollector") then watch(parent, "Enabled") end
                        parent = parent.Parent
                    end
                elseif object:IsA("TextLabel") then
                    local path = A.key(object.Parent and object.Parent.Name)
                    if path:find("notification", 1, true) or path:find("toast", 1, true) then
                        watch(object, "Text", function() if A.questCue(object.Text) then A.stateChanged() end end)
                    end
                end
            end
        end
        A.sourcesDirty = false
    end

    -- O HUD do Anime Piece pode mostrar apenas o nome da quest, o objetivo
    -- 'Defeat Higaro's bandits (2/5)' e o botao Cancel, sem texto "Quest".
    -- Identificar pelo conteudo e pela posicao na esquerda, nao pelo nome do Frame.
    function A.leftHudQuest()
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport or viewport.X <= 0 or viewport.Y <= 0 then return false end
        local leftLimit = math.min(viewport.X * 0.46, 560)
        local topLimit, bottomLimit = viewport.Y * 0.09, viewport.Y * 0.82
        local objectives, progresses, cancels = {}, {}, {}
        for object in pairs(World.gui) do
            if object.Parent and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
                and not object:IsDescendantOf(ScreenGui)
                and not object:FindFirstAncestorWhichIsA("BillboardGui")
                and not object:FindFirstAncestorWhichIsA("SurfaceGui")
                and A.visible(object) then
                local pos, size = object.AbsolutePosition, object.AbsoluteSize
                if size.X > 0 and size.Y > 0 and pos.X >= 0 and pos.X < leftLimit
                    and pos.Y >= topLimit and pos.Y < bottomLimit then
                    local raw = string.lower(A.markerText(object.Text or ""))
                    local key = A.key(raw)
                    local hasCount = raw:match("%d+%s*/%s*%d+") ~= nil
                        or raw:match("%d+%s+of%s+%d+") ~= nil
                    local objective = raw:match("%f[%a]defeat%f[%A]")
                        or raw:match("%f[%a]kill%f[%A]")
                        or raw:match("%f[%a]eliminate%f[%A]")
                        or raw:match("%f[%a]slay%f[%A]")
                        or raw:match("%f[%a]hunt%f[%A]")
                        or raw:match("%f[%a]collect%f[%A]")
                        or raw:match("%f[%a]gather%f[%A]")
                        or raw:match("%f[%a]derrotar%f[%A]")
                        or raw:match("%f[%a]derrote%f[%A]")
                        or raw:match("%f[%a]matar%f[%A]")
                        or raw:match("%f[%a]mate%f[%A]")
                    local center = Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
                    if objective then objectives[#objectives + 1] = {point=center, text=raw, count=hasCount} end
                    if hasCount then progresses[#progresses + 1] = {point=center, text=raw} end
                    if key == "cancel" or key == "cancelquest" or key == "cancelar"
                        or key == "abandonquest" or key == "abandon" then
                        cancels[#cancels + 1] = {point=center}
                    end
                end
            end
        end
        -- A barra de vida tambem tem 307/330, mas fica no rodape e nao
        -- contem objetivo de quest nem um botao Cancel proximo.
        local function nearby(a, b)
            return math.abs(a.point.X - b.point.X) <= 330
                and math.abs(a.point.Y - b.point.Y) <= 180
        end
        for _, objective in ipairs(objectives) do
            if objective.count then return true, objective.text end
            for _, progress in ipairs(progresses) do
                if nearby(objective, progress) then return true, objective.text end
            end
            for _, cancel in ipairs(cancels) do
                if nearby(objective, cancel) then return true, objective.text end
            end
        end
        for _, progress in ipairs(progresses) do
            for _, cancel in ipairs(cancels) do
                if nearby(progress, cancel) then return true, progress.text end
            end
        end
        return false
    end

    function A.readState()
        -- O painel no canto esquerdo tem prioridade sobre valores replicados
        -- desatualizados ou sobre o fim indicado pelo Auto Repeat Quest.
        local seen, objective = A.leftHudQuest()
        local now = os.clock()
        if seen then
            A.lastQuestHudSeenAt = now
            A.questHudSeenThisCycle = true
            A.questHudGoneSince = nil
            -- Uma missao com contador completo (ex.: 5/5) tambem e uma
            -- transicao valida no Auto Repeat. Sem isso, um painel que
            -- continua visivel em 5/5 impediria eternamente o retorno.
            local current, required = tostring(objective or ""):match("(%d+)%s*/%s*(%d+)")
            current, required = tonumber(current), tonumber(required)
            local complete = current and required and required > 0 and current >= required
            if complete and QuestRuntime.RepeatEnabled and (A.acceptedLock or A.questHudConfirmed) then
                A.questHudCompletedSince = A.questHudCompletedSince or now
                if now - A.questHudCompletedSince >= 1.5 then
                    QuestRuntime.QuestHudBlocking = false
                    QuestRuntime.RepeatCompletionPending = true
                    if not A.questHudCompletionLogged then
                        print("[Random Hub | Auto Quest] Objetivo completo (" .. current .. "/" .. required .. "); repetindo missao.")
                        A.questHudCompletionLogged = true
                    end
                    return false, "quest-hud-completed"
                end
            else
                A.questHudCompletedSince = nil
                A.questHudCompletionLogged = false
            end
            QuestRuntime.QuestHudBlocking = true
            A.questHudConfirmed = true
            if not A.questHudLogged then
                print("[Random Hub | Auto Quest] Quest ativa detectada no canto esquerdo: " .. tostring(objective))
                A.questHudLogged = true
            end
            return true, "quest-hud-left"
        end
        A.questHudCompletedSince = nil
        A.questHudGoneSince = A.questHudGoneSince or now
        -- Aguarda sumir por tempo suficiente para nao interpretar uma
        -- atualizacao da interface/streaming como fim da missao.
        if A.questHudSeenThisCycle and now - A.questHudGoneSince < 3 then
            QuestRuntime.QuestHudBlocking = true
            return nil, "quest-hud-grace"
        end
        QuestRuntime.QuestHudBlocking = false
        A.questHudLogged = false
        -- Depois de reconhecer a quest no HUD, a ausencia CONFIRMADA do
        -- painel tem prioridade sobre valores replicados antigos. Revalidar
        -- a cada ciclo permite aceitar a proxima missao quando a anterior
        -- sumir da tela, sem depender de reiniciar o toggle.
        if A.questHudSeenThisCycle and now - A.questHudGoneSince >= 3 then
            if not A.questHudEndLogged then
                print("[Random Hub | Auto Quest] Painel da missao desapareceu; liberando proxima quest.")
                A.questHudEndLogged = true
            end
            if QuestRuntime.RepeatEnabled and A.acceptedLock then
                QuestRuntime.RepeatCompletionPending = true
            end
            return false, "quest-hud-ended"
        end
        local flag, identity, hasIdentity, status, ended = nil, false, false, nil, false
        for _, source in ipairs(A.sources or {}) do
            local object = source.object
            if object.Parent then
                local ok, value = pcall(function()
                    if source.attribute then return object:GetAttribute(source.attribute) end
                    return object.Value
                end)
                if ok then
                    local active = A.valueActive(value)
                    if value == nil and source.role == "identity" and not source.attribute and object:IsA("ObjectValue") then active = false end
                    if source.role == "flag" and active ~= nil then flag = flag == true or active
                    elseif source.role == "identity" and active ~= nil then hasIdentity = true; identity = identity or active
                    elseif source.role == "ended" and active == true then ended = true
                    elseif source.role == "state" then
                        local key = A.key(value)
                        local running = {active=true,inprogress=true,accepted=true,running=true,started=true}
                        local inactive = {['']=true,none=true,idle=true,inactive=true,notstarted=true,finished=true,complete=true,completed=true,cancelled=true,canceled=true}
                        if running[key] then status = true elseif inactive[key] and status ~= true then status = false end
                    end
                end
            end
        end
        if flag == true then return true, "replicated" end
        if flag == nil and (status == true or (identity and not ended and status ~= false)) then return true, "replicated" end
        local known, active = false, false
        for panel, labels in pairs(A.panels or {}) do
            if panel.Parent then
                if not panel.Visible then known = true
                elseif A.visible(panel) then
                    local content, empty = false, false
                    for _, label in ipairs(labels) do
                        if label.Parent and A.visible(label) then
                            local key = A.key(label.Text)
                            if A.emptyQuestText(label.Text) then empty = true end
                            if key ~= "" and key ~= "quest" and key ~= "currentquest" and key ~= "mission" and key ~= "quests" then content = true end
                        end
                    end
                    known = true; active = active or (content and not empty)
                end
            end
        end
        if active then return true, "game-gui" end
        if flag ~= nil then return flag, "replicated" end
        if status ~= nil then return status, "replicated" end
        if hasIdentity then return identity and not ended, "replicated" end
        if known then return false, "game-gui" end
        if A.endedByRemoval then return false, "replicated-removal" end
        return nil, "unknown"
    end

    function A.emit(signal, ...)
        local sent = World.emit(signal, ...)
        if not sent then A.lastError = World.lastCallbackError end
        return sent
    end

    function A.buttonLabel(button)
        if button:IsA("TextButton") and A.key(button.Text) ~= "" then return A.key(button.Text) end
        local stack, visited = {{button,0}}, 0
        while #stack > 0 and visited < 40 do
            local item = table.remove(stack)
            local node, depth = item[1], item[2]
            if node ~= button and node:IsA("TextLabel") and A.key(node.Text) ~= "" then return A.key(node.Text) end
            if depth < 4 then for _, child in ipairs(node:GetChildren()) do stack[#stack + 1] = {child,depth + 1} end end
            visited = visited + 1
        end
        return A.key(button.Name):gsub("button$", "")
    end

    function A.actionKind(button)
        local label = A.buttonLabel(button)
        local menu = {quest=true,quests=true,viewquests=true}
        local accept = {sure=true,yes=true,accept=true,acceptquest=true,takequest=true,startquest=true,acceptmission=true,
            sim=true,aceitar=true,aceitarmissao=true,aceitarmisso=true,repeatquest=true,['repeat']=true,again=true,repetir=true}
        if menu[label] then return "menu" end
        if accept[label] then return "accept" end
    end

    function A.providerMatches(value, entry)
        if not entry then return false end
        local text = A.markerText(value)
        local key = A.key(text)
        if key == A.key(entry.name) then return true end
        local modelName = entry.modelName or (entry.model and entry.model.Name)
        local modelKey = A.key(modelName)
        if modelKey ~= "npc" and modelKey ~= "model" and modelKey ~= "npcmodel" and modelKey ~= "rig" and key == modelKey then return true end
        text = text:gsub("%s*[%[%(%-]?%s*[Ll][Vv]%.?%s*%d.*$", "")
            :gsub("%s*[%[%(%-]?%s*[Ll][Ee][Vv][Ee][Ll]%s*%d.*$", "")
        return A.key(text) == A.key(entry.name)
    end

    function A.dialogContext(button, entry)
        local node, fallback = button.Parent, nil
        local labels = {}
        for object in pairs(World.gui) do
            if object.Parent and object:IsA("TextLabel") and A.visible(object) then labels[#labels + 1] = object end
        end
        local context = {quest=false,provider=false,foreign=false,unrelated=false}
        for _ = 1, 7 do
            if not node or node:IsA("PlayerGui") or node:IsA("ScreenGui") then break end
            if node:IsA("Frame") or node:IsA("ScrollingFrame") then
                fallback = fallback or node
                local key = A.key(node.Name)
                local quest, provider, foreign, unrelated = A.questCue(key), false, false, false
                unrelated = key:find("trade", 1, true) or key:find("shop", 1, true) or key:find("fruitstock", 1, true)
                for _, label in ipairs(labels) do
                    if label:IsDescendantOf(node) then
                        local value, field = A.key(label.Text), A.key(label.Name)
                        quest = quest or A.questCue(label.Text)
                        provider = provider or A.providerMatches(label.Text, entry)
                        if entry and (field == "npcname" or field == "speakername") and value ~= "" and not A.providerMatches(label.Text, entry) then foreign = true end
                        unrelated = unrelated or value == "fruitstock" or value == "trade" or value == "shop"
                            or value:find("wouldyouliketobuy",1,true) or value:find("wouldyouliketotrade",1,true)
                    end
                end
                context = {root=node,quest=quest,provider=provider,foreign=foreign,unrelated=not not unrelated}
                if A.dialogName(node.Name) or provider or unrelated then return context end
            end
            node = node.Parent
        end
        context.root = context.root or fallback
        return context
    end

    function A.dialogButtons()
        local result, entry = {}, A.selected()
        for object in pairs(World.gui) do
            if object.Parent and object:IsA("GuiButton") and A.visible(object) and A.actionKind(object) then
                local context = A.dialogContext(object, entry)
                local own = entry and A.dialogForKey == entry.key and not A.beforeButtons[object]
                local modal = context.root and A.dialogName(context.root.Name)
                if context.root and not context.unrelated and not context.foreign and (context.provider or own or (context.quest and modal)) then
                    result[#result + 1] = object
                end
            end
        end
        table.sort(result, function(a,b)
            local ak, bk = A.actionKind(a), A.actionKind(b)
            local sureA,sureB=A.buttonLabel(a)=="sure",A.buttonLabel(b)=="sure"
            if sureA ~= sureB then return sureA end
            if ak ~= bk then return ak == "accept" end
            return a:GetFullName() < b:GetFullName()
        end)
        return result
    end

    function A.snapshotButtons()
        local result = {}
        for object in pairs(World.gui) do
            if object.Parent and object:IsA("GuiButton") and A.visible(object) then result[object] = true end
        end
        return result
    end

    function A.releaseGuiInput()
        local point = A.mouseDown
        A.mouseDown = nil
        if point then pcall(function() VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0) end) end
        if A.hiddenHub then
            ScreenGui.Enabled = A.hubWasEnabled and not destroyed and uiOpen ~= false
            A.hiddenHub, A.hubWasEnabled = nil, nil
        end
    end

    function A.activateButton(button)
        if not A.visible(button) or button.Active == false then return false end
        local readable, interactable = pcall(function() return button.Interactable end)
        if readable and interactable == false then return false end
        if A.emit(button.MouseButton1Click) or A.emit(button.Activated, nil, 1) then return true end
        local camera = workspace.CurrentCamera
        if not camera or button.AbsoluteSize.X <= 0 or button.AbsoluteSize.Y <= 0 then return false end
        local point, viewport = button.AbsolutePosition + button.AbsoluteSize / 2, camera.ViewportSize
        if point.X < 0 or point.Y < 0 or point.X >= viewport.X or point.Y >= viewport.Y then return false end
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        A.hubWasEnabled, A.hiddenHub = ScreenGui.Enabled, true
        ScreenGui.Enabled = false
        A.mouseDown = point
        local ok = pcall(function()
            VirtualInputManager:SendMouseMoveEvent(point.X, point.Y, game)
            VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
            task.wait(0.035)
        end)
        A.releaseGuiInput()
        return ok
    end

    function A.open(entry)
        if not entry or not entry.model.Parent then return false end
        local function sent(method)
            A.dialogForKey, A.lastOpenMechanism = entry.key, method
            return true
        end
        for _, prompt in ipairs(entry.prompts) do
            local action = A.key(prompt.ActionText)
            local excluded = A.excluded(prompt.ActionText .. " " .. prompt.ObjectText)
                or action:find("buy", 1, true) or action:find("purchase", 1, true) or action:find("trade", 1, true)
                or action:find("claim", 1, true) or action:find("abandon", 1, true) or action:find("complete", 1, true)
            if prompt.Parent and prompt.Enabled and not excluded then
                if type(fireproximityprompt) == "function" and pcall(fireproximityprompt, prompt) then return sent("native-prompt") end
                if A.emit(prompt.Triggered, LocalPlayer) then return sent("prompt-callback") end
                if PromptService and A.emit(PromptService.PromptTriggered, prompt, LocalPlayer) then return sent("prompt-service-callback") end
                local part = prompt:FindFirstAncestorWhichIsA("BasePart") or A.entityRoot(entry.model)
                local _, root = Motion.character()
                if part and root and (part.Position - root.Position).Magnitude <= prompt.MaxActivationDistance
                    and prompt.HoldDuration <= 3 then
                    A.heldPrompt = prompt
                    local ok = pcall(function()
                        prompt:InputHoldBegin()
                        task.wait(prompt.HoldDuration + 0.05)
                        prompt:InputHoldEnd()
                    end)
                    A.heldPrompt = nil
                    if ok then return sent("prompt-input") end
                end
            end
        end
        for _, detector in ipairs(entry.clicks) do
            if detector.Parent then
                if type(fireclickdetector) == "function" and pcall(fireclickdetector, detector) then return sent("native-click") end
                if A.emit(detector.MouseClick, LocalPlayer) then return sent("click-callback") end
            end
        end
        for _, button in ipairs(entry.guiButtons or {}) do
            if button.Parent and A.activateButton(button) then return sent("billboard-input") end
        end
        A.lastOpenMechanism = "unavailable"
        return false
    end

    function A.cancelDispatch()
        if A.heldPrompt then pcall(function() A.heldPrompt:InputHoldEnd() end); A.heldPrompt = nil end
        A.releaseGuiInput()
        if A.dispatch then pcall(task.cancel, A.dispatch); A.dispatch = nil end
        if A.ownsInput then QuestRuntime.Interacting = false; A.ownsInput = false end
    end

    function A.send(callback)
        if A.dispatch or QuestRuntime.FruitBuying or QuestRuntime.Interacting or QuestRuntime.ItemBusy or QuestRuntime.SkillBusy then return false end
        if not A.nearNpc(A.selected()) then return false end
        local token = A.generation
        A.ownsInput, QuestRuntime.Interacting = true, true
        A.dispatch = task.defer(function()
            local state=A.readState()
            if not A.enabled or token ~= A.generation
                or (state == true and not QuestRuntime.RepeatCompletionPending)
                or (state == nil and not A.initialProbe)
                or not A.nearNpc(A.selected()) then
                A.dispatch = nil
                if A.ownsInput then A.ownsInput, QuestRuntime.Interacting = false, false end
                return
            end
            local ok, result = pcall(callback)
            if token ~= A.generation then return end
            A.dispatch = nil
            if A.ownsInput then A.ownsInput, QuestRuntime.Interacting = false, false end
            A.lastDispatch = ok and result == true
            A.schedule(0.2)
        end)
        return true
    end

    function A.schedule(delay)
        if not A.enabled or destroyed then return end
        local due = os.clock() + (delay or 0)
        if A.timer and A.timerAt <= due then return end
        if A.timer then pcall(task.cancel, A.timer) end
        local token = A.generation
        A.timerAt = due
        A.timer = task.delay(math.max(0, due - os.clock()), function()
            A.timer = nil
            if token ~= A.generation or not A.enabled or destroyed then return end
            local ok, err = pcall(A.tick, os.clock())
            if not ok then
                A.cancelDispatch()
                A.phase, A.lastError = "SUSPENDED", tostring(err)
                if os.clock() - A.lastWarning > 10 then warn("[Random Hub | Auto Quest] " .. tostring(err)); A.lastWarning = os.clock() end
                -- Erro recuperavel: nao parar permanentemente a verificacao
                -- da quest. A thread anterior ja foi encerrada ao chegar aqui.
                A.schedule(1.5)
            end
        end)
    end

    function A.releaseMovement()
        if A.moving then Motion.release("Quest") end
        A.moving, QuestRuntime.AcceptanceMoving = false, false
        A.approachStarted, A.nearSince = nil, nil
    end

    function A.holdAcceptedQuest(source)
        -- A quest confirmed by the game's replicated state or quest HUD is a
        -- one-way transition for this Auto Quest activation. Never reaccept it
        -- automatically when the quest UI changes or the quest is completed.
        A.acceptedLock, A.activeLatch, A.confirmed = true, true, true
        A.questHudEndLogged = false
        A.questHudConfirmed = true
        A.phase, A.attempts, A.sentAcceptance = "ACTIVE_WAIT_FARM", 0, false
        A.waitConfirmationAt, A.inactiveSince, A.noQuestSince = nil, nil, nil
        A.cancelDispatch()
        A.releaseMovement()
        QuestRuntime.QuestPriority = false
        QuestRuntime.RepeatCompletionPending = false
        QuestRuntime.RepeatAtQuestNpc = false
        QuestRuntime.RepeatArmAt = os.clock() + 3
        -- Quem ja escolheu um mob nao precisa seleciona-lo novamente em cada quest.
        QuestRuntime.WaitForFarmSelection = not QuestRuntime.HasFarmSelection
        print("[Random Hub | Auto Get Quest] Quest accepted.")
    end

    function A.talkSettings(entry)
        local root = A.entityRoot(entry.model)
        if not root then return nil end
        local part, range = root, 5
        for _, prompt in ipairs(entry.prompts or {}) do
            if prompt.Parent and prompt.Enabled and prompt.MaxActivationDistance > 0 then
                part = prompt:FindFirstAncestorWhichIsA("BasePart") or root
                range = math.min(5, prompt.MaxActivationDistance * 0.8)
                break
            end
        end
        if part == root then
            for _, click in ipairs(entry.clicks or {}) do
                if click.Parent and click.MaxActivationDistance > 0 then
                    part = click:FindFirstAncestorWhichIsA("BasePart") or root
                    range = math.min(5, click.MaxActivationDistance * 0.8)
                    break
                end
            end
        end
        local target = range < 2.5 and part or root
        return target, part, math.max(0.25, range), math.min(3, math.max(0.2, range * 0.5))
    end

    function A.nearNpc(entry)
        if not entry or not entry.model.Parent or not entry.model:IsDescendantOf(workspace) then return false end
        local _, root = Motion.character()
        local target, part, range = A.talkSettings(entry)
        return root ~= nil and target ~= nil and (root.Position - part.Position).Magnitude <= range
    end

    function A.moveNear(entry, now)
        local target, part, range, spacing = A.talkSettings(entry)
        if not target or not Motion.allowed("Quest") then return false end
        if not A.moving then
            A.moving, QuestRuntime.AcceptanceMoving = true, true
            if QuestRuntime.StopFarmSearch then QuestRuntime.StopFarmSearch() end
            if QuestRuntime.StopItems then QuestRuntime.StopItems() end
            if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
            A.approachStarted = now
            local _, playerRoot = Motion.character()
            A.approachDistance = playerRoot and (playerRoot.Position - part.Position).Magnitude or 0
        end
        if not Motion.request("Quest", target, spacing, "giver") then return false end
        return A.nearNpc(entry)
    end

    -- Tenta interagir como um jogador: mira no NPC, move o cursor,
    -- aperta o botao esquerdo, segura brevemente e solta. Nenhum evento
    -- interno do NPC e disparado antes dessa tentativa visivel.
    function A.humanClickNpc(entry)
        if not A.enabled or not A.nearNpc(entry) then return false end
        local camera = workspace.CurrentCamera
        local model = entry.model
        if not camera or not model or not model.Parent then return false end
        local part = model:FindFirstChild("Head", true)
            or model:FindFirstChild("UpperTorso", true)
            or model:FindFirstChild("Torso", true)
            or A.entityRoot(model)
        if not part or not part:IsA("BasePart") then return false end

        -- Deixa o NPC no centro da visao antes do clique.
        local cameraPosition = camera.CFrame.Position
        if (part.Position - cameraPosition).Magnitude > 0.05 then
            pcall(function()
                camera.CFrame = CFrame.lookAt(cameraPosition, part.Position)
            end)
        end
        task.wait(0.08)
        if not A.enabled or not A.nearNpc(entry)
            or (A.readState() == true and not QuestRuntime.RepeatCompletionPending) then return false end

        local point, visible = camera:WorldToViewportPoint(part.Position)
        if not visible or point.Z <= 0 then return false end
        local viewport = camera.ViewportSize
        local x, y = math.floor(point.X), math.floor(point.Y)
        if x <= 1 or y <= 1 or x >= viewport.X - 1 or y >= viewport.Y - 1 then return false end
        local mousePoint = Vector2.new(x, y)
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end

        -- Oculta apenas o Random Hub durante o clique, evitando que
        -- um controle da propria interface intercepte o mouse.
        A.hubWasEnabled, A.hiddenHub, A.mouseDown = ScreenGui.Enabled, true, mousePoint
        ScreenGui.Enabled = false
        local downOK, upOK = false, false
        if VirtualInputManager then
            pcall(function() VirtualInputManager:SendMouseMoveEvent(x, y, game) end)
            downOK = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            end)
            if downOK then task.wait(0.12) end
            upOK = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
        end
        local clicked = downOK and upOK
        if not clicked and VirtualUser then
            -- Alternativa para executores que nao enviam eventos pelo VIM.
            local cf = camera.CFrame
            pcall(function() VirtualUser:CaptureController() end)
            local pressed = pcall(function() VirtualUser:Button1Down(mousePoint, cf) end)
            if pressed then task.wait(0.12) end
            local released = pcall(function() VirtualUser:Button1Up(mousePoint, cf) end)
            clicked = pressed and released
            if not clicked then
                pcall(function() VirtualUser:Button1Up(mousePoint, cf) end)
            end
        end
        A.releaseGuiInput() -- Sempre solta o mouse e restaura a UI.
        if clicked then
            A.dialogForKey, A.lastOpenMechanism = entry.key, "human-left-click"
        else
            warn("[Random Hub | Auto Quest] Falha ao enviar clique de mouse (VIM e VirtualUser).")
        end
        return clicked
    end

    local openNearby = A.open
    function A.open(entry)
        if not A.nearNpc(entry)
            or (A.readState() == true and not QuestRuntime.RepeatCompletionPending) then return false end
        -- Primeiro, clique fisico no NPC. Na proxima tentativa, se o dialogo
        -- nao apareceu, experimenta a interacao nativa do jogo como fallback.
        -- Evita ficar repetindo apenas um metodo que nao abre a conversa.
        if (A.attempts or 1) % 2 == 1 then
            if A.humanClickNpc(entry) then return true end
            return openNearby(entry)
        end
        if openNearby(entry) then return true end
        return A.humanClickNpc(entry)
    end

    function A.pause(reason)
        if not A.enabled then return end
        A.generation = A.generation + 1
        if A.timer then pcall(task.cancel,A.timer); A.timer = nil end
        A.cancelDispatch()
        A.releaseMovement()
        A.phase = A.sentAcceptance and "WAIT_CONFIRMATION" or (reason == "respawn" and "WAIT_RESPAWN" or "WAIT_MOVEMENT")
        A.schedule(0.5)
    end
    QuestRuntime.CancelAcceptance = A.pause
    -- A thread do Auto Repeat nao pode conduzir o movimento, mas pode solicitar
    -- que o Auto Quest reavalie a conclusao mais cedo.
    QuestRuntime.RequestAcceptanceUpdate = function()
        if A.enabled and not destroyed then A.schedule(0.15) end
    end

    function A.tick(now)
        if not A.enabled or destroyed then return end
        if World.characterUnavailable or (not A.manualCatalog and not World.ready) or not Motion.character() then
            A.cancelDispatch(); A.releaseMovement(); A.schedule(0.5); return
        end
        if A.catalogDirty and now >= (A.nextCatalogAt or 0) then A.refreshCatalog()
        elseif A.catalogDirty and A.requestCatalog then A.requestCatalog() end
        if A.sourcesDirty then A.refreshSources() end
        -- Read actual quest state BEFORE choosing a target or walking to the NPC.
        -- A confirmed active quest always stops acceptance/teleport attempts.
        local active, source = A.readState()
        A.stateSource = source
        -- Se o painel esquerdo existe, a quest pertence ao jogador. Isso
        -- supera qualquer pedido de repeticao ou retorno ao NPC.
        if source == "quest-hud-left" or source == "quest-hud-grace" then
            QuestRuntime.QuestPriority = false
            QuestRuntime.RepeatAtQuestNpc = false
            A.noQuestSince = nil
            A.endedByRemoval = false
            if active == true and not A.acceptedLock then A.holdAcceptedQuest(source) end
            A.releaseMovement()
            A.schedule(0.5)
            return
        end
        -- A missao concluida pode continuar marcada como ativa ate a entrega.
        -- O Auto Repeat autoriza o retorno somente com sinal de conclusao.
        local repeatFinished = QuestRuntime.RepeatEnabled
            and QuestRuntime.RepeatCompletionPending
        if active == true and not repeatFinished then
            QuestRuntime.QuestPriority = false
            QuestRuntime.RepeatAtQuestNpc = false
            A.noQuestSince = nil
            A.endedByRemoval = false
            if not A.acceptedLock then A.holdAcceptedQuest(source) end
            A.releaseMovement()
            A.schedule(0.65) -- keep watching for quest completion
            return
        end

        -- A ausencia de quest ou a conclusao confirmada retoma o controle
        -- do personagem antes do proximo teleporte do Auto Farm.
        if repeatFinished or (active == false and source ~= "unknown") then
            QuestRuntime.QuestPriority = true
            if Motion.owner == "Farm" then Motion.release("Farm") end
            if QuestRuntime.StopFarmSearch then QuestRuntime.StopFarmSearch() end
        end
        if A.acceptedLock then
            A.releaseMovement()
            if repeatFinished then
                A.acceptedLock, A.activeLatch, A.confirmed = false, false, false
                A.sentAcceptance, A.endedByRemoval = false, false
                A.noQuestSince, A.inactiveSince = nil, now - 1
                A.phase, A.nextAttempt = "READY", now
                QuestRuntime.WaitForFarmSelection = false
                A.schedule(0.1)
                return
            end
            -- Only return to the quest NPC after an EXPLICIT, stable no-quest
            -- indication. Nil/unknown readings never undo a confirmed quest.
            if active == false and source ~= "unknown" then
                A.noQuestSince = A.noQuestSince or now
                if now - A.noQuestSince >= 2.5 then
                    -- No Repeat, a transicao de quest ativa -> nenhuma quest
                    -- tambem significa que a proxima repeticao pode ser buscada.
                    if QuestRuntime.RepeatEnabled then
                        QuestRuntime.RepeatCompletionPending = true
                    end
                    A.acceptedLock, A.activeLatch, A.confirmed = false, false, false
                    A.sentAcceptance, A.endedByRemoval = false, false
                    A.noQuestSince, A.inactiveSince = nil, now
                    A.phase, A.nextAttempt = "READY", now + 0.75
                    QuestRuntime.WaitForFarmSelection = false
                    A.schedule(0.75)
                else
                    A.schedule(0.5)
                end
            else
                A.noQuestSince = nil
                A.phase = "ACTIVE_WAIT_FARM"
                A.schedule(0.75)
            end
            return
        end

        -- After clicking Sure!, never travel back to the NPC while the quest
        -- status is active or unknown. Retry only after a stable no-quest state.
        if A.sentAcceptance then
            A.waitConfirmationAt = A.waitConfirmationAt or now
            A.phase = "WAIT_QUEST_CONFIRMATION"
            A.releaseMovement()
            if active == false and source ~= "unknown" then
                A.noQuestSince = A.noQuestSince or now
            else
                A.noQuestSince = nil
            end
            if now - A.waitConfirmationAt >= 10
                and A.noQuestSince and now - A.noQuestSince >= 2.5 then
                A.sentAcceptance, A.waitConfirmationAt, A.probeUsed = false, nil, false
                A.noQuestSince = nil
                A.sentButtons, A.beforeButtons, A.dialogForKey = {}, {}, nil
                A.phase, A.nextAttempt = "READY", now + 3
                A.schedule(3)
            else
                A.schedule(0.5)
            end
            return
        end
        if A.phase == "SUSPENDED" then
            A.phase, A.nextAttempt = "READY", now + 4
            A.schedule(4)
            return
        end
        local inDialog = A.phase == "OPENING" or A.phase == "CONFIRMING"
        if active == nil and A.probeUsed and not inDialog then
            if now - (A.lastProbeAt or now) < 8 then
                A.phase = "WAIT_DIALOG"; A.releaseMovement(); A.schedule(0.5)
                return
            end
            A.probeUsed = false
        end
        A.initialProbe = active == nil
        A.inactiveSince = A.inactiveSince or now
        if now-A.inactiveSince < 0.8 then A.schedule(0.8); return end
        local entry = A.selected()
        if not entry then
            QuestRuntime.QuestPriority = false
            QuestRuntime.RepeatAtQuestNpc = false
            A.cancelDispatch(); A.releaseMovement(); A.phase="WAIT_NPC"
            A.schedule(0.75)
            return
        end
        -- O Auto Quest vai buscar a missao, mesmo que o Auto Farm esteja ativo.
        QuestRuntime.QuestPriority = true
        if Motion.owner == "Farm" then Motion.release("Farm") end
        if not Motion.allowed("Quest") or QuestRuntime.FruitBuying or QuestRuntime.SkillBusy
            or (QuestRuntime.Interacting and not A.ownsInput) then
            A.cancelDispatch(); A.releaseMovement()
            if not inDialog then A.phase="WAIT_MOVEMENT" end
            A.schedule(0.4); return
        end
        if not A.moveNear(entry,now) then
            QuestRuntime.RepeatAtQuestNpc = false
            local approachTimeout = SafeMode.Enabled and math.clamp((A.approachDistance or 0) / math.max(1, SafeMode.walkSpeed()) + 45, 35, 600) or 22
            if A.approachStarted and now-A.approachStarted > approachTimeout then
                -- Restart the movement request after a cooldown instead of
                -- permanently suspending the selected quest NPC.
                A.cancelDispatch(); A.releaseMovement()
                A.phase, A.nextAttempt = "RETRY_APPROACH", now + 1.5
                A.schedule(1.5); return
            end
            if not inDialog then A.phase="APPROACH" end
            A.nearSince=nil; A.schedule(0.2); return
        end
        A.nearSince = A.nearSince or now
        -- Wait a FULL second after arriving / the last NPC teleport before
        -- clicking the world or interacting with the conversation.
        local arrivedAt = math.max(A.nearSince, Motion.lastQuestGiverTeleportAt or -math.huge)
        QuestRuntime.RepeatAtQuestNpc = now - arrivedAt >= 1
        if now - arrivedAt < 1 then A.schedule(math.max(0.05, 1 - (now - arrivedAt))); return end
        if A.dispatch then A.schedule(0.2); return end
        if inDialog then
            if now >= A.deadline then
                A.cancelDispatch(); A.releaseMovement()
                -- No successful acceptance was confirmed: retry at a low
                -- frequency, even if the dialog was already open initially.
                A.probeUsed, A.lastProbeAt = false, nil
                A.beforeButtons, A.sentButtons, A.dialogForKey = {}, {}, nil
                local delay = math.min(9, math.max(2, A.attempts * 2))
                A.phase, A.nextAttempt = "READY", now + delay
                A.schedule(delay); return
            end
            for _, button in ipairs(A.dialogButtons()) do
                local label = A.buttonLabel(button)
                local context = A.dialogContext(button,entry)
                local action = A.actionKind(button)
                -- Ao repetir, o NPC pode exibir Repeat Quest, Accept ou Yes
                -- em vez de Sure!. Continuamos priorizando Sure! na ordenacao.
                if (label == "sure" or action == "accept" or action == "menu")
                    and (not A.beforeButtons[button] or context.provider)
                    and A.sentButtons[button] ~= label then
                    A.phase="CONFIRMING"
                    local queued=A.send(function()
                        if not A.nearNpc(entry) or not A.visible(button) then return false end
                        local sent=A.activateButton(button)
                        if sent and action == "accept" then A.sentAcceptance=true end
                        return sent
                    end)
                    if queued then A.sentButtons[button]=label end
                    break
                end
            end
            A.schedule(0.3); return
        end
        if now < (A.nextAttempt or 0) then A.schedule(A.nextAttempt-now); return end
        local existing=A.dialogButtons()
        for _, button in ipairs(existing) do
            local context=A.dialogContext(button,entry)
            if context.provider and not context.foreign and not context.unrelated then
                A.dialogForKey=entry.key
                A.beforeButtons,A.sentButtons,A.sentAcceptance={},{},false
                A.phase,A.deadline="CONFIRMING",now+7
                A.schedule(0.1); return
            end
        end
        if #existing>0 then A.phase="WAIT_DIALOG"; A.releaseMovement(); A.schedule(0.5); return end
        A.beforeButtons,A.sentButtons=A.snapshotButtons(),{}
        A.sentAcceptance,A.dialogForKey=false,nil
        A.attempts=A.attempts+1
        A.phase,A.deadline="OPENING",now+7
        A.send(function()
            local sent=A.open(entry)
            if sent then A.probeUsed, A.lastProbeAt = true, os.clock() end
            return sent
        end)
        A.schedule(0.2)
    end

    function A.setEnabled(state)
        A.generation = A.generation + 1
        A.enabled = state == true and not destroyed
        if A.timer then pcall(task.cancel, A.timer); A.timer = nil end
        A.cancelDispatch()
        A.releaseMovement()
        A.probeUsed, A.initialProbe = false, false
        A.disconnect(A.sourceConnections)
        A.phase, A.attempts, A.inactiveSince, A.nextAttempt = A.enabled and "UNKNOWN" or "OFF", 0, nil, 0
        A.sentButtons, A.beforeButtons = {}, {}
        A.sentAcceptance, A.endedByRemoval, A.confirmed, A.dialogForKey = false, false, false, nil
        A.acceptedLock, A.waitConfirmationAt, A.lastProbeAt, A.noQuestSince = false, nil, nil, nil
        Motion.lastQuestGiverTeleportAt = nil
        -- Switching Auto Quest off clears the hold; switching it on will
        -- re-arm the wait until the next explicit mob selection.
        QuestRuntime.WaitForFarmSelection = false
        QuestRuntime.QuestPriority = false
        QuestRuntime.RepeatAtQuestNpc = false
        QuestRuntime.RepeatCompletionPending = false
        QuestRuntime.QuestHudBlocking = false
        A.lastQuestHudSeenAt, A.questHudLogged = nil, false
        A.questHudSeenThisCycle, A.questHudConfirmed = false, false
        A.questHudGoneSince, A.questHudCompletedSince = nil, nil
        A.questHudCompletionLogged, A.questHudEndLogged = false, false
        QuestRuntime.AcceptOnlyEnabled = A.enabled
        A.sourcesDirty, A.catalogDirty = true, true
        if not A.stopping and QuestRuntime.CancelInteraction then QuestRuntime.CancelInteraction() end
        if A.enabled then
            A.startDiscovery()
            A.schedule(0)
        elseif Pages.AutoQuest.Visible then A.startDiscovery()
        else A.stopDiscovery() end
    end

    function A.select(key)
        if A.selectedKey == key then return end
        local enabled = A.enabled
        A.selectedKey = key
        if enabled then A.setEnabled(true) end
    end

    World.onQuestObjectChanged = function(object, removed)
        if object:IsDescendantOf(ScreenGui) then return end
        A.trackCatalog(object, removed)
        if (object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("GuiObject")) and A.markerBoard(object) then return end
        local gui = object:IsA("PlayerGui") or object:FindFirstAncestorWhichIsA("PlayerGui")
        if gui then
            local relevant = A.questCue(object.Name) or A.questPanel(object) ~= nil
            local parent = object.Parent
            for _ = 1, 8 do
                if not parent or parent:IsA("PlayerGui") then break end
                local key = A.key(parent.Name)
                if key:find("dialog", 1, true) or key:find("notification", 1, true) or key:find("toast", 1, true) then relevant = true; break end
                parent = parent.Parent
            end
            if relevant and A.enabled then A.sourcesDirty = true; A.schedule(0.25) end
            return
        end
        if object:IsDescendantOf(LocalPlayer) and A.dataEligible(object) then
            if A.enabled then
                if removed and A.acceptedLock and not World.characterUnavailable then
                    A.endedByRemoval = true
                end
                A.sourcesDirty = true; A.schedule(0.25)
            end
            return
        end
    end
    Stoppers.QuestAcceptance = function()
        QuestRuntime.WaitForFarmSelection = false
        QuestRuntime.QuestPriority = false
        QuestRuntime.RepeatAtQuestNpc = false
        QuestRuntime.RepeatCompletionPending = false
        QuestRuntime.RequestAcceptanceUpdate = nil
        A.stopping = true
        A.setEnabled(false)
        A.stopDiscovery()
        if A.catalogTimer then pcall(task.cancel, A.catalogTimer); A.catalogTimer = nil end
        World.onQuestObjectChanged = nil
        QuestRuntime.CancelAcceptance = nil
    end
end)


runSection("QuestNPCs", function()
    local A = AcceptQuest
    -- Coordinates transcribed from the 27 screenshots supplied by the user.
    A.manualCatalog = {
        {"Zack",0,440.9,11.3,-991.5},
        {"Mari",10,153.1,11.3,-948.9},
        {"Roupão",20,13.7,10.9,-1142.1},
        {"Bob",30,-4.6,10.9,-992.0},
        {"Relouneibor",40,235.6,10.9,-1442.3},
        {"Adventurer",45,-905.7,12.2,104.0},
        {"Melancio",60,-1244.4,12.4,32.6},
        {"Adventurer Girl",70,-1158.0,12.2,-14.8},
        {"Luna",75,785.6,6.1,2682.9},
        {"Gunks",85,535.6,6.0,2901.9},
        {"Kairon",90,379.2,6.2,3183.6},
        {"Lazy Guy",100,660.7,5.9,2687.5},
        {"Shiro",105,379.2,6.2,3266.6},
        {"Jaquin",110,618.9,6.7,2913.4},
        {"Yoko",115,1309.8,5.8,3566.8},
        {"Kaito",120,240.7,5.8,3515.5},
        {"Naori",130,1103.1,5.9,2762.2},
        {"Noob Player",135,3697.9,33.6,2578.0},
        {"Romantic Player",145,3575.9,33.9,2607.0},
        {"Master Player",150,3335.0,33.6,2777.0},
        {"Miner Player",160,3813.8,33.9,2924.0},
        {"Novice Sorcerer",165,4154.9,9.9,44.7},
        {"Ryoto",180,4239.4,12.5,116.1},
        {"Yaz",190,4504.3,9.9,-14.4},
        {"Nando",205,4683.5,9.9,-79.7},
        {"Chokita",215,4509.2,12.0,337.5},
        {"Lito",225,4603.3,9.9,205.7},
    }

    function A.npcKey(value)
        local text=tostring(value or ""):lower():gsub("<[^>]*>","")
        for accent,plain in pairs({["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["é"]="e",["ê"]="e",
            ["í"]="i",["ó"]="o",["ô"]="o",["õ"]="o",["ú"]="u",["ç"]="c"}) do text=text:gsub(accent,plain) end
        return (text:gsub("[^%w]",""))
    end
    function A.bindManual(entry)
        if entry.model and entry.model.Parent and entry.model:IsDescendantOf(workspace) then return entry end
        entry.model = nil
        local now = os.clock()
        if now < (entry.nextBindAt or 0) then return entry end
        entry.nextBindAt = now + 0.6
        local seen, winner, best = {}, nil, 45*45
        local function consider(model,namedMarker)
            if not model or seen[model] or not model:IsA("Model") or model == LocalPlayer.Character
                or Players:GetPlayerFromCharacter(model) then return end
            seen[model] = true
            if not model.Parent or not model:IsDescendantOf(workspace)
                or model:FindFirstAncestorWhichIsA("Camera") or model:FindFirstAncestorWhichIsA("WorldModel") then return end
            local root = A.entityRoot(model)
            if not root then return end
            local delta = root.Position - entry.position
            local distance = delta:Dot(delta)
            if distance > best then return end
            local humanoid = getMobHumanoid(model)
            local matches = namedMarker or A.npcKey(model.Name) == A.npcKey(entry.name)
                or (humanoid and A.npcKey(humanoid.DisplayName) == A.npcKey(entry.name))
            local generic = A.npcKey(model.Name) == "npc" or A.npcKey(model.Name) == "rig" or A.npcKey(model.Name) == "model"
            if not matches and not generic and not (humanoid and distance<=20*20) then return end
            local hasQuestMarker = false
            local prompts, clicks, labels = {}, {}, {}
            for _, child in ipairs(model:GetDescendants()) do
                if child:IsA("ProximityPrompt") then prompts[#prompts+1] = child
                elseif child:IsA("ClickDetector") then clicks[#clicks+1] = child
                elseif (child:IsA("TextLabel") or child:IsA("TextButton")) and A.markerBoard(child) then
                    labels[#labels+1] = child
                    matches = matches or A.npcKey(child.Text) == A.npcKey(entry.name)
                    hasQuestMarker = hasQuestMarker or A.questionCue(child.Text) or A.questMarker(child.Text)
                end
            end
            -- Generic "NPC" rigs are allowed only at this exact saved NPC point
            -- and with a real quest marker. A nearby enemy cannot become the giver.
            if not matches and not (generic and hasQuestMarker and distance <= 12*12) then return end
            winner, best = {model=model,prompts=prompts,clicks=clicks,markers=labels}, distance
        end
        local ok, parts = pcall(function() return workspace:GetPartBoundsInRadius(entry.position,45) end)
        if ok then for _, part in ipairs(parts) do consider(A.npcFor(part)) end end
        for humanoid in pairs(World.humanoids) do consider(humanoid.Parent) end
        for text in pairs(World.texts) do
            if text.Parent and A.markerBoard(text) and A.npcKey(text.Text) == A.npcKey(entry.name) then
                -- A verified nameplate also identifies NPCs with generic model IDs.
                local model=A.npcFor(text)
                if model then seen[model]=nil end
                consider(model,true)
            end
        end
        if winner then
            entry.model, entry.modelName = winner.model, winner.model.Name
            entry.prompts, entry.clicks, entry.markers = winner.prompts, winner.clicks, winner.markers
        end
        return entry
    end
    function A.refreshCatalog()
        local entries = {}
        for _, row in ipairs(A.manualCatalog) do
            local key = "manual:" .. row[2] .. ":" .. A.npcKey(row[1])
            local entry = A.entries[key] or {key=key,manual=true,name=row[1],minLevel=row[2],
                position=Vector3.new(row[3],row[4],row[5]),prompts={},clicks={},markers={},guiButtons={}}
            entries[key] = entry
            if key == A.selectedKey then A.bindManual(entry) end
        end
        A.entries, A.catalogDirty, A.nextCatalogAt = entries, false, os.clock()+1
        if A.refreshDropdown then A.refreshDropdown() end
    end
    function A.startDiscovery()
        -- This catalog is manual. Do not stream remote islands to populate it.
        A.catalogDirty = true
    end
    function A.selected()
        local entry = A.selectedKey and A.entries[A.selectedKey]
        return entry and A.bindManual(entry) or nil
    end
    local nearNpc, moveNear = A.nearNpc, A.moveNear
    function A.nearNpc(entry)
        return entry and entry.model and nearNpc(entry) or false
    end
    function A.moveNear(entry, now)
        A.bindManual(entry)
        if entry.model then return moveNear(entry,now) end
        if not Motion.allowed("Quest") then return false end
        A.moving, QuestRuntime.AcceptanceMoving = true, true
        if not A.approachStarted then
            local _, root = Motion.character()
            A.approachStarted, A.approachDistance = now, root and (root.Position-entry.position).Magnitude or 0
        end
        -- Reuse the existing Quest/giver teleport, streaming, Safe Farm and
        -- cancellation guards while the NPC is still outside the loaded region.
        Motion.request("Quest",nil,0,"giver",entry.position+Vector3.new(0,2,0))
        return false
    end

    A.refreshCatalog()
end)

runSection("QuestAcceptanceUI", function()
    local A = AcceptQuest
    local page = Pages.AutoQuest
    createCombatToggle(page, "AutoQuestAcceptToggleCard", "Auto Get Quest", 2, A.setEnabled)
    local card = createStyledCard(page, "SelectQuestNPCCard", 82, 3)
    local title = Instance.new("TextLabel")
    title.Name = "SelectQuestNPCTitle"
    title.Size = UDim2.new(1, -24, 0, 22)
    title.Position = UDim2.fromOffset(12, 7)
    title.BackgroundTransparency = 1
    title.Text = "Select Quest NPC"
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    local selection = Instance.new("TextButton")
    selection.Name = "QuestNPCSelection"
    selection.Size = UDim2.new(1, -24, 0, 36)
    selection.Position = UDim2.fromOffset(12, 34)
    selection.BackgroundColor3 = Theme.BgSecondary
    selection.BorderSizePixel = 0
    selection.Text = "Select Quest NPC"
    selection.TextColor3 = Theme.Text
    selection.Font = Enum.Font.Gotham
    selection.TextSize = 13
    selection.AutoButtonColor = false
    selection.Parent = card
    addCorner(selection, 8)
    addStroke(selection, Theme.Stroke, 1, 0.4)
    local list = Instance.new("ScrollingFrame")
    list.Name = "QuestNPCOptions"
    list.Position = UDim2.fromOffset(12, 78)
    list.Size = UDim2.new(1, -24, 0, 164)
    list.BackgroundColor3 = Theme.BgSecondary
    list.BorderSizePixel = 0
    list.Visible = false
    list.ScrollBarThickness = 4
    list.ScrollBarImageColor3 = Theme.Accent2
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.Parent = card
    addCorner(list, 8)
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = list
    local padding = Instance.new("UIPadding")
    padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
    padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
    padding.Parent = list
    local rows, rowConnections = {}, {}
    local function setOpen(state)
        list.Visible = state
        card.Size = UDim2.new(1, 0, 0, state and 254 or 82)
    end
    function A.refreshDropdown()
        for _, connection in ipairs(rowConnections) do connection:Disconnect() end
        table.clear(rowConnections)
        for _, row in ipairs(rows) do row:Destroy() end
        table.clear(rows)
        local entries = {}
        for _, entry in pairs(A.entries) do entries[#entries + 1] = entry end
        table.sort(entries, function(a, b)
            if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
            if a.name ~= b.name then return a.name < b.name end
            return a.key < b.key
        end)
        local names = {}
        for _, entry in ipairs(entries) do names[entry.name] = (names[entry.name] or 0) + 1 end
        for index, entry in ipairs(entries) do
            local row = Instance.new("TextButton")
            row.Name = "QuestNPCOption"
            row.Size = UDim2.new(1, -4, 0, 32)
            row.LayoutOrder = index
            row.BackgroundColor3 = entry.key == A.selectedKey and Theme.Accent2 or Theme.Card
            row.BorderSizePixel = 0
            row.Text = A.displayName(entry)
            if names[entry.name] > 1 then
                local island = World.islandFor(entry.model)
                row.Text = A.displayName(entry) .. " (" .. (island and island.Name or entry.islandName or tostring(index)) .. ")"
            end
            row.TextColor3 = Theme.Text
            row.Font = Enum.Font.Gotham
            row.TextSize = 12
            row.Parent = list
            addCorner(row, 6)
            rows[#rows + 1] = row
            rowConnections[#rowConnections + 1] = row.MouseButton1Click:Connect(function()
                A.select(entry.key)
                selection.Text = A.displayName(entry)
                setOpen(false)
                A.refreshDropdown()
            end)
        end
        if #entries == 0 then
            local empty = Instance.new("TextLabel")
            empty.Name = "EmptyQuestNPCList"
            empty.Size = UDim2.new(1, -4, 0, 32)
            empty.BackgroundTransparency = 1
            empty.Text = "No quest NPC found"
            empty.TextColor3 = Theme.TextDim
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.Parent = list
            rows[#rows + 1] = empty
        end
        local selected = A.selected()
        local known = selected or (A.selectedKey and A.entries[A.selectedKey])
        selection.Text = known and A.displayName(known) or "Select Quest NPC"
    end
    function A.requestCatalog()
        if not A.catalogActive() then return end
        A.startDiscovery()
        if A.catalogTimer then return end
        local delay = math.max(0.2, (A.nextCatalogAt or 0) - os.clock())
        A.catalogTimer = task.delay(delay, function()
            A.catalogTimer = nil
            if not A.catalogActive() then return end
            if A.catalogDirty then
                local ok, err = pcall(A.refreshCatalog)
                if not ok then
                    A.lastCatalogError = tostring(err)
                    if os.clock() - A.lastWarning > 10 then warn("[Random Hub | Quest NPC] " .. tostring(err)); A.lastWarning = os.clock() end
                end
            end
        end)
    end
    connect(selection.MouseButton1Click, function()
        setOpen(not list.Visible)
        if list.Visible then A.catalogDirty = true; A.requestCatalog() end
    end)
    connect(page:GetPropertyChangedSignal("Visible"), function()
        if page.Visible then A.catalogDirty = true; A.requestCatalog()
        else
            setOpen(false)
            if not A.enabled then A.stopDiscovery() end
        end
    end)
    Stoppers.QuestNPCDropdown = function()
        for _, connection in ipairs(rowConnections) do connection:Disconnect() end
        if A.catalogTimer then pcall(task.cancel, A.catalogTimer); A.catalogTimer = nil end
    end
end)


local FruitShop = {
    enabled = false, generation = 0, selected = {}, ledger = {}, rows = {}, availability = {}, previousStock = {},
    cycle = 0, dirty = true, nextScan = 0, nextOpen = 0, openAttempts = 0, connections = {}, bound = {},
}

runSection("FruitShop", function()
    local B = FruitShop
    local A = AcceptQuest
    local PromptService = getServiceSafe("ProximityPromptService")

    function B.text(object)
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            return tostring(object.Text or ""):gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
        end
        return ""
    end

    function B.cashPrice(text)
        local number, suffix = tostring(text or ""):gsub("<[^>]*>", ""):match("^%s*%$%s*(%d[%d,%.]*)%s*([kKmMbB]?)%s*$")
        if not number then return nil end
        number = tonumber((number:gsub(",", "")))
        if not number or number <= 0 then return nil end
        local multiplier = ({k=1000,m=1000000,b=1000000000})[string.lower(suffix)] or 1
        return number * multiplier
    end

    function B.logicalVisible(object, root)
        if not object or not object.Parent then return false end
        local node = object
        while node and node ~= root do
            if node:IsA("GuiObject") and not node.Visible then return false end
            node = node.Parent
        end
        return node == root
    end

    function B.premium(button)
        local stack = {button}
        while #stack > 0 do
            local node = table.remove(stack)
            local value = A.key(node.Name .. " " .. B.text(node))
            if value:find("robux", 1, true) or value:find("gift", 1, true)
                or value:find("permanent", 1, true) or value:find("gamepass", 1, true) then return true end
            for _, child in ipairs(node:GetChildren()) do stack[#stack + 1] = child end
        end
        return false
    end

    function B.priceButton(label, row)
        local node = label
        while node and node ~= row do
            if node:IsA("GuiButton") then return not B.premium(node) and node or nil end
            node = node.Parent
        end
        local parent = label.Parent
        if not parent then return nil end
        local candidates = {}
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiButton") and not B.premium(child) then candidates[#candidates + 1] = child end
        end
        if #candidates == 1 then return candidates[1] end
        local point = label.AbsolutePosition + label.AbsoluteSize / 2
        local match
        for _, button in ipairs(candidates) do
            local p, size = button.AbsolutePosition, button.AbsoluteSize
            if point.X >= p.X and point.X <= p.X + size.X and point.Y >= p.Y and point.Y <= p.Y + size.Y then
                if match then return nil end
                match = button
            end
        end
        return match
    end

    function B.findRoot()
        for title in pairs(World.gui) do
            if title.Parent and title:IsA("TextLabel") and not title:IsDescendantOf(ScreenGui) and A.key(B.text(title)) == "fruitstock" then
                local node = title.Parent
                for _ = 1, 7 do
                    if not node or node:IsA("PlayerGui") then break end
                    if node:IsA("ScreenGui") and not A.key(node.Name):find("fruitstock", 1, true) then break end
                    local count = 0
                    for object in pairs(World.gui) do
                        if object.Parent and object:IsA("TextLabel") and object:IsDescendantOf(node) and World.fruitAlias(B.text(object)) then count = count + 1 end
                    end
                    if count > 0 then return node end
                    node = node.Parent
                end
            end
        end
    end

    function B.rowFor(title, root, titles, objects)
        local row = title.Parent
        for _ = 1, 7 do
            if not row or row == root.Parent then return nil end
            local names, unique = 0, {}
            for _, other in ipairs(titles) do
                local name = World.fruitAlias(B.text(other))
                if name and not unique[name] and other:IsDescendantOf(row) then unique[name] = true; names = names + 1 end
            end
            if names > 1 then return nil end
            local stock, cash, button, cashLabel = true, nil, nil, nil
            for _, object in ipairs(objects) do
                if object:IsDescendantOf(row) and B.logicalVisible(object, root) then
                    local text = B.text(object)
                    if A.key(text) == "outofstock" then stock = false end
                    local price = B.cashPrice(text)
                    if price then
                        local candidate = B.priceButton(object, row)
                        if candidate and B.logicalVisible(candidate, root) then
                            local enabled, interactable = pcall(function() return candidate.Interactable end)
                            if candidate.Active ~= false and (not enabled or interactable ~= false) then
                                if button and button ~= candidate then return nil end
                                cash, button, cashLabel = price, candidate, object
                            end
                        end
                    end
                end
            end
            if cash or not stock then return {row = row, title = title, label = cashLabel, name = World.fruitAlias(B.text(title)), price = cash, button = button, inStock = stock and button ~= nil} end
            if row == root then return nil end
            row = row.Parent
        end
    end

    function B.invalidate()
        if B.enabled then B.dirty = true; B.nextScan = 0 end
    end

    function B.disconnect()
        for object, connections in pairs(B.bound) do
            for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
            B.bound[object] = nil
        end
    end

    function B.readBalance()
        if B.balanceNode and B.balanceNode.Parent then return tonumber(B.balanceNode.Value) end
        local best, priority = nil, -1
        local ranks = {money=6,cash=5,beli=4,berries=4,coins=1}
        for object in pairs(World.stats) do
            local rank = ranks[A.key(object.Name)]
            if rank and rank > priority and object.Parent and (object:IsA("NumberValue") or object:IsA("IntValue")) then
                local node, valid = object.Parent, true
                while node and node ~= LocalPlayer do
                    local key = A.key(node.Name)
                    if key:find("quest",1,true) or key:find("reward",1,true) or key:find("price",1,true) or node:IsA("PlayerScripts") then valid = false; break end
                    node = node.Parent
                end
                if valid then best, priority, B.balanceNode = tonumber(object.Value), rank, object end
            end
        end
        if best ~= nil then return best end
        for object in pairs(World.gui) do
            if object.Parent and not object:IsDescendantOf(ScreenGui) then
                local value = string.lower(B.text(object)):match("^money%s*:?%s*([%d,%.]+)%s*$")
                if value then return tonumber((value:gsub(",", ""))) end
            end
        end
    end

    function B.inventory()
        local counts = {}
        local function add(container)
            if not container then return end
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local name = World.fruitDisplay(tool)
                    if name then counts[name] = (counts[name] or 0) + 1 end
                end
            end
        end
        add(LocalPlayer:FindFirstChildOfClass("Backpack")); add(LocalPlayer.Character)
        return counts
    end

    function B.equippedFruit()
        local fields = {fruit=true,currentfruit=true,equippedfruit=true,devilfruit=true}
        for object in pairs(World.stats) do
            if object.Parent and object:IsA("StringValue") and fields[A.key(object.Name)] then
                local name = World.fruitAlias(object.Value)
                if name then return name end
            end
        end
    end

    function B.scan()
        B.root = B.findRoot()
        B.rows, B.dirty, B.nextScan = {}, false, os.clock() + 5
        for object, connections in pairs(B.bound) do
            if not B.root or not object.Parent or not object:IsDescendantOf(B.root) then
                for _, connection in ipairs(connections) do connection:Disconnect() end
                B.bound[object] = nil
            end
        end
        if not B.root then return end
        B.openAttempts = 0
        local titles, objects = {}, {}
        for object in pairs(World.gui) do
            if object.Parent and object:IsDescendantOf(B.root) then
                objects[#objects + 1] = object
                if object:IsA("TextLabel") and World.fruitAlias(B.text(object)) then titles[#titles + 1] = object end
            end
        end
        for _, title in ipairs(titles) do
            local row = B.rowFor(title, B.root, titles, objects)
            if row then
                B.rows[row.name] = row
                local previous = B.previousStock[row.name]
                if previous == false and row.inStock then B.availability[row.name] = (B.availability[row.name] or 0) + 1 end
                B.previousStock[row.name] = row.inStock
            end
        end
        for _, object in ipairs(objects) do
            if not B.bound[object] then
                local connections = {}
                B.bound[object] = connections
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                connections[#connections + 1] = object:GetPropertyChangedSignal("Text"):Connect(function()
                    local h, m, s = B.text(object):match("^(%d+):(%d%d):(%d%d)$")
                    if h then
                        local remaining = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                        if B.remaining and remaining > B.remaining + 5 then B.cycle = B.cycle + 1; B.invalidate() end
                        B.remaining = remaining
                    else B.invalidate() end
                end)
                local h, m, s = B.text(object):match("^(%d+):(%d%d):(%d%d)$")
                if h then
                    local remaining = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
                    if B.remaining and remaining > B.remaining + 5 then B.cycle = B.cycle + 1 end
                    B.remaining = remaining
                end
            end
            if object:IsA("GuiObject") then connections[#connections + 1] = object:GetPropertyChangedSignal("Visible"):Connect(B.invalidate) end
            end
        end
    end

    function B.openStock()
        for object in pairs(World.gui) do
            if object.Parent and object:IsA("GuiButton") and not object:IsDescendantOf(ScreenGui)
                and (A.key(B.text(object)) == "fruitstock" or A.key(object.Name):gsub("button$", "") == "fruitstock") then
                if A.emit(object.MouseButton1Click) or A.emit(object.Activated, nil, 1) then return true end
            end
        end
        local seen = {}
        local function try(model)
            if not model or seen[model] or not model.Parent or model == LocalPlayer.Character or Players:GetPlayerFromCharacter(model) then return false end
            seen[model] = true
            for _, object in ipairs(model:GetDescendants()) do
                if object:IsA("ProximityPrompt") and object.Enabled then
                    if A.emit(object.Triggered, LocalPlayer) then return true end
                    if PromptService and A.emit(PromptService.PromptTriggered, object, LocalPlayer) then return true end
                elseif object:IsA("ClickDetector") and A.emit(object.MouseClick, LocalPlayer) then return true end
            end
            return false
        end
        for humanoid in pairs(World.humanoids) do
            local model = humanoid.Parent
            if model and (A.key(model.Name) == "fruitstock" or A.key(humanoid.DisplayName) == "fruitstock") and try(model) then return true end
        end
        for text in pairs(World.texts) do
            if text.Parent and A.key(B.text(text)) == "fruitstock" and text:FindFirstAncestorWhichIsA("BillboardGui") then
                if try(A.npcFor(text)) then return true end
            end
        end
        return false
    end

    function B.release()
        if B.ownsInput then QuestRuntime.Interacting = false end
        B.ownsInput, QuestRuntime.FruitBuying = false, false
    end

    function B.dispatchAction(callback)
        if B.dispatch or QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving or QuestRuntime.ItemBusy or QuestRuntime.SkillBusy then return false end
        local token = B.generation
        B.ownsInput, QuestRuntime.Interacting, QuestRuntime.FruitBuying = true, true, true
        B.dispatch = task.defer(function()
            if not B.enabled or token ~= B.generation then return end
            local ok, result = pcall(callback)
            if token ~= B.generation then return end
            B.dispatch = nil
            B.lastDispatch = ok and result == true
            B.release()
            B.invalidate()
        end)
        return true
    end

    function B.tick(now)
        if not B.enabled or World.characterUnavailable or not World.ready then return end
        if B.pending then
            local pending = B.pending
            local balance, inventory = B.readBalance(), B.inventory()
            local confirmed = (inventory[pending.name] or 0) > pending.count
                or (B.equippedFruit() == pending.name and pending.equipped ~= pending.name)
                or (balance ~= nil and pending.balance ~= nil and balance <= pending.balance - pending.price)
            if confirmed or now >= pending.deadline then
                B.lastResult = confirmed and "confirmed" or "unconfirmed"
                B.pending = nil
                if B.dispatch then pcall(task.cancel, B.dispatch); B.dispatch = nil end
                B.release()
            end
            return
        end
        if B.dispatch or QuestRuntime.Interacting or QuestRuntime.AcceptanceMoving or QuestRuntime.ItemBusy or QuestRuntime.SkillBusy or A.dispatch
            or (A.enabled and (A.phase == "OPENING" or A.phase == "CONFIRMING")) then return end
        local chosen = false
        for _, name in ipairs(World.fruitCatalog) do if B.selected[name] then chosen = true; break end end
        if not chosen then return end
        if B.dirty or now >= B.nextScan then B.scan() end
        if not B.root then
            if now >= B.nextOpen and B.openAttempts < 3 then
                B.openAttempts = B.openAttempts + 1
                B.nextOpen = now + B.openAttempts * 10
                B.dispatchAction(B.openStock)
            end
            return
        end
        if not A.visible(B.root) and not B.contextTried then
            B.contextTried = true
            B.dispatchAction(B.openStock)
            return
        end
        local balance = B.readBalance()
        for _, name in ipairs(World.fruitCatalog) do
            local row, previous = B.rows[name], B.ledger[name]
            if B.selected[name] and row and row.inStock and row.button and row.button.Parent
                and not B.premium(row.button) and (balance == nil or balance >= row.price)
                and (not previous or previous.cycle ~= B.cycle or previous.available ~= (B.availability[name] or 0) or previous.price ~= row.price) then
                local inventory = B.inventory()
                B.ledger[name] = {cycle = B.cycle, available = B.availability[name] or 0, price = row.price}
                B.pending = {name = name, price = row.price, count = inventory[name] or 0,
                    balance = balance, equipped = B.equippedFruit(), deadline = now + 8}
                B.dispatchAction(function()
                    if not B.selected[name] or not row.button.Parent or B.premium(row.button)
                        or not B.logicalVisible(row.button, B.root) or World.fruitAlias(B.text(row.title)) ~= name
                        or not row.label.Parent or not B.logicalVisible(row.label, B.root)
                        or B.cashPrice(B.text(row.label)) ~= row.price or row.button.Active == false then return false end
                    for object in pairs(World.gui) do
                        if object.Parent and object:IsDescendantOf(row.row) and B.logicalVisible(object, B.root)
                            and A.key(B.text(object)) == "outofstock" then return false end
                    end
                    return A.emit(row.button.MouseButton1Click) or A.emit(row.button.Activated, nil, 1)
                end)
                break
            end
        end
    end

    function B.setEnabled(state)
        B.generation = B.generation + 1
        B.enabled = state == true and not destroyed
        if B.worker then pcall(task.cancel, B.worker); B.worker = nil end
        if B.dispatch then pcall(task.cancel, B.dispatch); B.dispatch = nil end
        B.release()
        B.disconnect()
        B.pending, B.ledger, B.openAttempts, B.nextOpen, B.dirty, B.contextTried = nil, {}, 0, 0, true, false
        World.onFruitShopGuiChanged = nil
        if not B.enabled then return end
        World.onFruitShopGuiChanged = function(object)
            if object:IsDescendantOf(ScreenGui) then return end
            local node = object
            for _ = 1, 8 do
                if not node then break end
                if A.key(node.Name):find("fruitstock", 1, true) or A.key(B.text(node)) == "fruitstock"
                    or (B.root and node == B.root) then B.invalidate(); break end
                node = node.Parent
            end
        end
        local token = B.generation
        B.worker = task.spawn(function()
            while B.enabled and token == B.generation and not destroyed do
                local ok, err = pcall(B.tick, os.clock())
                if not ok then
                    B.lastError = tostring(err)
                    if B.dispatch then pcall(task.cancel, B.dispatch); B.dispatch = nil end
                    B.pending = nil
                    B.release()
                end
                task.wait(B.pending and 0.25 or 0.8)
            end
        end)
    end

    function B.select(name, state)
        name = World.fruitAlias(name)
        if not name then return end
        if state and not B.selected[name] then B.ledger[name] = nil end
        B.selected[name] = state == true or nil
        if not state and B.pending and B.pending.name == name then
            if B.dispatch then pcall(task.cancel, B.dispatch); B.dispatch = nil end
            B.pending = nil; B.release()
        end
        B.invalidate()
    end

    Stoppers.FruitShop = function() B.setEnabled(false) end
end)


-- AUTO SPIN FRUIT | eventos virtuais, mesma estrategia de Auto Buy Fruit.
-- Nao controla camera, mouse ou teleporte. So executa callbacks conhecidos.
local FruitSpin = {
    enabled = false, generation = 0, worker = nil, dispatch = nil,
    pending = nil, nextAction = 0, failures = 0, lastWarn = -math.huge,
    price = 10000, openAttempts = 0, ownsInput = false,
}

runSection("FruitSpin", function()
    local S = FruitSpin
    local A = AcceptQuest
    local B = FruitShop
    local PromptService = getServiceSafe("ProximityPromptService")

    function S.warn(message)
        if os.clock() - S.lastWarn > 8 then
            S.lastWarn = os.clock()
            warn("[Random Hub | Auto Spin Fruit] " .. tostring(message))
        end
    end

    function S.balance()
        local amount = B.readBalance()
        if amount ~= nil then return amount end
        local camera = workspace.CurrentCamera
        local vp = camera and camera.ViewportSize
        if not vp then return nil end
        for item in pairs(World.gui) do
            if item.Parent and item:IsA("TextLabel") and A.visible(item) then
                local point = item.AbsolutePosition
                if point.X <= vp.X * 0.4 and point.Y >= vp.Y * 0.5 then
                    local val = B.text(item):match("^%s*%$%s*([%d,]+)%s*$")
                    if val then return tonumber((val:gsub(",", ""))) end
                end
            end
        end
        return nil
    end

    function S.fruitCount()
        local total = 0
        for _, count in pairs(B.inventory()) do total = total + count end
        return total
    end

    -- Associa um dialogo exclusivamente ao Fruit Gacha, nao a quests com Sure!.
    function S.dialogButton()
        local labels, buttons = {}, {}
        for item in pairs(World.gui) do
            if item.Parent and not item:IsDescendantOf(ScreenGui) and A.visible(item) then
                if item:IsA("TextLabel") or item:IsA("TextButton") then
                    local t = string.lower(A.markerText(item.Text or ""))
                    if (t:find("spin", 1, true) or t:find("roll", 1, true))
                        and t:find("fruit", 1, true)
                        and (t:find("would you", 1, true) or t:find("for $", 1, true)
                            or t:find("gacha", 1, true)) then
                        labels[#labels + 1] = item
                    end
                end
                if item:IsA("GuiButton") and item.Active ~= false then
                    local name = A.buttonLabel(item)
                    if name == "sure" or name == "spin" or name == "yes" then
                        buttons[#buttons + 1] = item
                    end
                end
            end
        end
        local chosen, best = nil, math.huge
        for _, label in ipairs(labels) do
            local gui = label:FindFirstAncestorWhichIsA("ScreenGui")
            local origin = label.AbsolutePosition + label.AbsoluteSize / 2
            for _, button in ipairs(buttons) do
                if gui and gui == button:FindFirstAncestorWhichIsA("ScreenGui") then
                    local distance = (button.AbsolutePosition + button.AbsoluteSize / 2 - origin).Magnitude
                    if distance < 550 and distance < best then chosen, best = button, distance end
                end
            end
        end
        return chosen
    end

    function S.isGachaNpc(model)
        if not model or not model.Parent or model == LocalPlayer.Character
            or (model:IsA("Model") and Players:GetPlayerFromCharacter(model)) then return false end
        local name = A.key(model.Name)
        if name == "luzefe" or name:find("fruitgacha", 1, true)
            or name:find("gachafruit", 1, true) then return true end
        if model:IsA("Model") then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and A.key(hum.DisplayName) == "luzefe" then return true end
            for _, child in ipairs(model:GetDescendants()) do
                if (child:IsA("TextLabel") or child:IsA("TextButton")) and A.markerBoard(child) then
                    local text = A.key(child.Text)
                    if text == "luzefe" or text:find("fruitgacha", 1, true) then return true end
                end
            end
        end
        return false
    end

    function S.findNpc()
        for hum in pairs(World.humanoids) do
            if hum.Parent and S.isGachaNpc(hum.Parent) then return hum.Parent end
        end
        for text in pairs(World.texts) do
            if text.Parent and (text:IsA("TextLabel") or text:IsA("TextButton")) and A.markerBoard(text) then
                local key = A.key(text.Text)
                if key == "luzefe" or key:find("fruitgacha", 1, true) then
                    local npc = A.npcFor(text)
                    if npc and npc.Parent and S.isGachaNpc(npc) then return npc end
                end
            end
        end
        return nil
    end

    function S.release()
        if S.ownsInput then
            QuestRuntime.Interacting, QuestRuntime.FruitBuying = false, false
            S.ownsInput = false
        end
    end

    function S.dispatchAction(callback)
        if S.dispatch or QuestRuntime.Interacting or QuestRuntime.FruitBuying
            or QuestRuntime.AcceptanceMoving or QuestRuntime.ItemBusy
            or QuestRuntime.SkillBusy or A.dispatch or B.dispatch then return false end
        local token = S.generation
        S.ownsInput, QuestRuntime.Interacting, QuestRuntime.FruitBuying = true, true, true
        S.dispatch = task.spawn(function()
            local ok, result = pcall(function()
                if destroyed or not S.enabled or token ~= S.generation then return false end
                return callback()
            end)
            if token ~= S.generation then return end
            S.dispatch = nil
            S.release()
            S.lastResult = ok and result == true
            if not ok then S.warn(result) end
        end)
        return true
    end

    -- Mesmo mecanismo do Auto Buy Fruit: emitir sinais dos objetos (callbacks da GUI / NPC).
    function S.openVirtual()
        if S.dialogButton() then return true end
        -- Primeiro tenta botoes de GUI existentes para abrir o Fruit Gacha.
        for item in pairs(World.gui) do
            if item.Parent and item:IsA("GuiButton") and not item:IsDescendantOf(ScreenGui)
                and A.visible(item) and item.Active ~= false then
                local key = A.buttonLabel(item)
                if key == "fruitgacha" or key == "gachafruit" or key == "spinfruit" or key == "fruitspin" then
                    if A.emit(item.MouseButton1Click) or A.emit(item.Activated, nil, 1) then return true end
                end
            end
        end
        local npc = S.findNpc()
        if not npc then S.warn("Fruit Gacha / Luzefe ainda nao foi replicado no cliente."); return false end
        -- Nenhuma distancia e alterada aqui: funciona como o openStock() do Auto Buy.
        for _, item in ipairs(npc:GetDescendants()) do
            if item:IsA("ClickDetector") then
                if A.emit(item.MouseClick, LocalPlayer) then return true end
            elseif item:IsA("ProximityPrompt") and item.Enabled then
                if A.emit(item.Triggered, LocalPlayer) then return true end
                if PromptService and A.emit(PromptService.PromptTriggered, item, LocalPlayer) then return true end
            end
        end
        -- Fallback exclusivamente virtual, se as funcoes estiverem no executor.
        for _, item in ipairs(npc:GetDescendants()) do
            if item:IsA("ClickDetector") and type(fireclickdetector) == "function" then
                if pcall(fireclickdetector, item) then return true end
            elseif item:IsA("ProximityPrompt") and item.Enabled and type(fireproximityprompt) == "function" then
                if pcall(fireproximityprompt, item) then return true end
            end
        end
        S.warn("Sem callback virtual do Fruit Gacha. O executor pode nao expor os eventos do NPC.")
        return false
    end

    function S.confirmVirtual(button)
        if not button or not button.Parent or not A.visible(button) or button.Active == false
            or S.dialogButton() ~= button then return false end
        local ok, interactable = pcall(function() return button.Interactable end)
        if ok and interactable == false then return false end
        -- Segue exatamente o padrao do Auto Buy: MouseButton1Click / Activated.
        local fired = A.emit(button.MouseButton1Click) or A.emit(button.Activated, nil, 1)
        if fired then return true end
        -- Activate() e virtual: nao move cursor nem gera clique de mouse.
        return pcall(function() button:Activate() end)
    end

    function S.tick(now)
        if not S.enabled or destroyed or not World.ready or World.characterUnavailable then return end
        if S.dispatch then return end
        if S.pending then
            local pending = S.pending
            local balance, count = S.balance(), S.fruitCount()
            local confirmed = (balance ~= nil and pending.balance ~= nil and balance < pending.balance)
                or count > pending.count
            if confirmed then
                S.pending, S.failures, S.openAttempts = nil, 0, 0
                S.nextAction = now + 3
                return
            end
            if now < pending.deadline then return end
            S.pending = nil
            S.failures = S.failures + 1
            S.nextAction = now + math.min(26, 6 + S.failures * 4)
            S.warn("Giro nao confirmado; nao vou acionar Sure! novamente sem intervalo.")
            return
        end
        if now < S.nextAction then return end
        local balance = S.balance()
        if balance ~= nil and balance < S.price then S.nextAction = now + 8; return end
        if QuestRuntime.Interacting or QuestRuntime.FruitBuying or QuestRuntime.AcceptanceMoving
            or QuestRuntime.ItemBusy or QuestRuntime.SkillBusy or A.dispatch or B.dispatch then
            S.nextAction = now + 1
            return
        end
        local sure = S.dialogButton()
        if sure then
            local previousBalance, previousCount = balance, S.fruitCount()
            if S.dispatchAction(function()
                local sent = S.confirmVirtual(sure)
                if sent then
                    S.pending = {balance = previousBalance, count = previousCount, deadline = os.clock() + 11}
                end
                return sent
            end) then S.nextAction = now + 1.5 end
            return
        end
        if S.dispatchAction(S.openVirtual) then
            S.openAttempts = S.openAttempts + 1
            S.nextAction = now + math.min(10, 2 + S.openAttempts)
        else S.nextAction = now + 1 end
    end

    function S.setEnabled(value)
        S.generation = S.generation + 1
        S.enabled = value == true and not destroyed
        if S.worker then pcall(task.cancel, S.worker); S.worker = nil end
        if S.dispatch then pcall(task.cancel, S.dispatch); S.dispatch = nil end
        S.release()
        S.pending, S.nextAction, S.failures, S.openAttempts = nil, 0, 0, 0
        if not S.enabled then return end
        local token = S.generation
        S.worker = task.spawn(function()
            while S.enabled and S.generation == token and not destroyed do
                local ok, err = pcall(S.tick, os.clock())
                if not ok then S.warn(err); S.nextAction = os.clock() + 4; S.release() end
                task.wait(0.5)
            end
        end)
    end
    Stoppers.FruitSpin = function() S.setEnabled(false) end
end)

runSection("FruitShopUI", function()
    local B = FruitShop
    local page = Pages.Fruit
    createCombatToggle(page, "AutoBuyFruitToggleCard", "Auto Buy Fruit", 1, B.setEnabled)
    local card = createStyledCard(page, "SelectBuyFruitCard", 82, 2)
    local title = Instance.new("TextLabel")
    title.Name = "SelectBuyFruitTitle"
    title.Size = UDim2.new(1, -24, 0, 22)
    title.Position = UDim2.fromOffset(12, 7)
    title.BackgroundTransparency = 1
    title.Text = "Select Fruits to Buy"
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    local selection = Instance.new("TextButton")
    selection.Name = "FruitBuySelection"
    selection.Size = UDim2.new(1, -24, 0, 36)
    selection.Position = UDim2.fromOffset(12, 34)
    selection.BackgroundColor3 = Theme.BgSecondary
    selection.BorderSizePixel = 0
    selection.Text = "Select Fruits to Buy"
    selection.TextColor3 = Theme.Text
    selection.Font = Enum.Font.Gotham
    selection.TextSize = 13
    selection.TextTruncate = Enum.TextTruncate.AtEnd
    selection.AutoButtonColor = false
    selection.Parent = card
    addCorner(selection, 8)
    addStroke(selection, Theme.Stroke, 1, 0.4)
    local list = Instance.new("ScrollingFrame")
    list.Name = "FruitBuyOptions"
    list.Position = UDim2.fromOffset(12, 78)
    list.Size = UDim2.new(1, -24, 0, 164)
    list.BackgroundColor3 = Theme.BgSecondary
    list.BorderSizePixel = 0
    list.Visible = false
    list.ScrollBarThickness = 4
    list.ScrollBarImageColor3 = Theme.Accent2
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.Parent = card
    addCorner(list, 8)
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = list
    local padding = Instance.new("UIPadding")
    padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
    padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
    padding.Parent = list
    local rows = {}
    local function render()
        local names = {}
        for _, name in ipairs(World.fruitCatalog) do
            local selected = B.selected[name] == true
            local row = rows[name]
            row.Text = (selected and "✓  " or "    ") .. name
            row.BackgroundColor3 = selected and Theme.Accent2 or Theme.Card
            if selected then names[#names + 1] = name end
        end
        selection.Text = (#names > 0 and table.concat(names, ", ") or "Select Fruits to Buy")
    end
    for index, name in ipairs(World.fruitCatalog) do
        local row = Instance.new("TextButton")
        row.Name = "FruitBuy_" .. name
        row.Size = UDim2.new(1, -4, 0, 32)
        row.LayoutOrder = index
        row.BackgroundColor3 = Theme.Card
        row.BorderSizePixel = 0
        row.Text = "    " .. name
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.TextColor3 = Theme.Text
        row.Font = Enum.Font.Gotham
        row.TextSize = 12
        row.Parent = list
        addCorner(row, 6)
        rows[name] = row
        connect(row.MouseButton1Click, function()
            B.select(name, not B.selected[name])
            render()
        end)
    end
    connect(selection.MouseButton1Click, function()
        list.Visible = not list.Visible
        card.Size = UDim2.new(1, 0, 0, list.Visible and 254 or 82)
    end)
end)


runSection("AutoFarm", function()
    local AutoFarmPage = Pages.AutoFarm

    local AutoFarmCard = createStyledCard(AutoFarmPage, "AutoFarmCard", 52, 1)
    local AutoFarmTitle = Instance.new("TextLabel")
    AutoFarmTitle.Name = "AutoFarmTitle"
    AutoFarmTitle.Size = UDim2.new(1, -100, 0, 26)
    AutoFarmTitle.Position = UDim2.fromOffset(16, 11)
    AutoFarmTitle.BackgroundTransparency = 1
    AutoFarmTitle.Text = "Auto Farm"
    AutoFarmTitle.TextColor3 = Theme.Text
    AutoFarmTitle.Font = Enum.Font.GothamBold
    AutoFarmTitle.TextSize = 15
    AutoFarmTitle.TextXAlignment = Enum.TextXAlignment.Left
    AutoFarmTitle.Parent = AutoFarmCard

    local FarmToggle = Instance.new("TextButton")
    FarmToggle.Name = "AutoFarmToggle"
    FarmToggle.Size = UDim2.fromOffset(52, 28)
    FarmToggle.Position = UDim2.new(1, -68, 0, 11)
    FarmToggle.BackgroundColor3 = Color3.new(1, 1, 1)
    FarmToggle.BorderSizePixel = 0
    FarmToggle.Text = ""
    FarmToggle.AutoButtonColor = false
    FarmToggle.Parent = AutoFarmCard
    addCorner(FarmToggle, 14)
    local FarmToggleStroke = addStroke(FarmToggle, Theme.Stroke, 1, 0.3)
    local FarmToggleGradient = Instance.new("UIGradient")
    FarmToggleGradient.Color = TOGGLE_OFF
    FarmToggleGradient.Parent = FarmToggle
    local FarmToggleKnob = Instance.new("Frame")
    FarmToggleKnob.Name = "Knob"
    FarmToggleKnob.Size = UDim2.fromOffset(22, 22)
    FarmToggleKnob.Position = UDim2.new(0, 3, 0.5, -11)
    FarmToggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    FarmToggleKnob.BorderSizePixel = 0
    FarmToggleKnob.Parent = FarmToggle
    addCorner(FarmToggleKnob, 11)

    local function setFarmStatus(_message)
    end

    local autoFarmEnabled = false
    local autoFarmGeneration = 0
    local autoFarmThread = nil
    local farmTarget = nil
    local farmKilledCurrent = false
    local selectedFarmMobNames = {}
    local currentFarmMobIndex = 1
    local renderedFarmMobNames = {}
    local farmMobRowButtons = {}
    local farmMobRowConnections = {}
    local farmMobListInitialized = false
    local FarmMobList
    local FarmSelectionButton
    local FarmTargetDropdown
    local MiniBossDropdown
    local BossDropdown
    local stopMiniBoss
    local closeMiniBossDropdown
    local refreshFarmMobTypes
    local startAutoFarm
    local knownFarmMobNames = {}
    local knownFarmMobLevels = {}
    local knownFarmMobSources = setmetatable({}, {__mode = "k"})
    local knownFarmMobLocations = {}
    local nextTargetStreamAt = {}
    local knownRegionThread

    local farmIdentityCache = setmetatable({}, {__mode="k"})
    local function farmLevel(value)
        local text = tostring(value or ""):lower():gsub("<[^>]*>", "")
        return tonumber(text:match("level%s*:?%s*(%d+)")
            or text:match("%f[%a]lvl?%.?%s*:?%s*(%d+)")
            or text:match("%[%s*lv%.?%s*(%d+)%s*%]")
            or text:match("%[%s*(%d+)%s*%+%s*%]"))
    end
    local function farmNameKey(value)
        local text = tostring(value or ""):lower():gsub("<[^>]*>", "")
        text = text:gsub("%b[]", function(block)
            return (block:find("level",1,true) or block:find("lv",1,true)) and " " or block
        end):gsub("%b()", function(block)
            return (block:find("level",1,true) or block:find("lv",1,true)) and " " or block
        end)
        text = text:gsub("%f[%a]level%s*%d+", ""):gsub("%f[%a]lvl?%.?%s*%d+", "")
            :gsub("^npc[_%s%-]+", ""):gsub("^mob[_%s%-]+", ""):gsub("[_#]%d+$", "")
        return (text:gsub("[^%w]", ""))
    end

    local function farmIdentity(model)
        local now = os.clock()
        local humanoid = getMobHumanoid(model)
        local display = humanoid and humanoid.DisplayName or ""
        local cached = farmIdentityCache[model]
        if cached and cached.name == model.Name and cached.display == display and now < cached.expires then return cached end
        local result = {name=model.Name,display=display,keys={},expires=now + 4,label=model.Name}
        local function add(value)
            if type(value) ~= "string" or value == "" then return end
            local key = farmNameKey(value)
            if key ~= "" and key ~= "humanoid" and key ~= "npc" and key ~= "model" and key ~= "rig" then result.keys[key] = true end
            local catalog = World.FarmCatalog
            if catalog and catalog.labelKey then
                local matched, boss = catalog.labelKey(value)
                if matched then result.keys[matched] = true end
                if boss then result.boss = true end
            end
        end
        add(model.Name)
        if display ~= "" and display ~= "Humanoid" then add(display); result.label = display end
        for _, field in ipairs({"MobName","EnemyName","DisplayName"}) do
            local ok,value = pcall(function() return model:GetAttribute(field) end)
            if ok and type(value) == "string" and value ~= "" then add(value); result.label = value end
        end
        for _, object in ipairs(model:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton"))
                and (object:FindFirstAncestorWhichIsA("BillboardGui") or object:FindFirstAncestorWhichIsA("SurfaceGui")) then
                local field = object.Name:lower()
                local text = tostring(object.Text):gsub("<[^>]*>", "")
                local catalog=World.FarmCatalog
                local matched,boss
                if catalog and catalog.labelKey then matched,boss=catalog.labelKey(text) end
                local knownLabel=matched~=nil
                if boss then result.boss=true end
                if (field:find("name",1,true) or field:find("title",1,true) or knownLabel) and text:find("%a")
                    and (knownLabel or not text:find("%d+%s*/%s*%d+")) and not text:lower():find("quest",1,true) then
                    add(text)
                    if knownLabel or display == "" or display == "Humanoid" or farmNameKey(model.Name) == "npc" then result.label = text end
                end
            elseif object:IsA("StringValue") and (object.Name=="MobName" or object.Name=="EnemyName" or object.Name=="DisplayName") then
                add(object.Value)
                if type(object.Value)=="string" and object.Value~="" then result.label=object.Value end
            end
        end
        if result.label == "" or result.label == "Humanoid" then result.label = model.Name end
        result.level=farmLevel(result.name) or farmLevel(result.display) or farmLevel(result.label)
        if not result.level then
            for _, attribute in ipairs({"Level", "Lvl", "MobLevel", "EnemyLevel", "NPCLevel"}) do
                local value = model:GetAttribute(attribute)
                result.level = tonumber(value) or farmLevel(value)
                if result.level then break end
            end
        end
        if not result.level then
            for _, child in ipairs(model:GetDescendants()) do
                if child:IsA("TextLabel") and child:FindFirstAncestorWhichIsA("BillboardGui") then
                    result.level = farmLevel(child.Text) or farmLevel(child.Name)
                    if result.level then break end
                elseif child:IsA("IntValue") or child:IsA("NumberValue") then
                    local lower = child.Name:lower()
                    if lower == "level" or lower == "lvl" or lower == "moblevel" then
                        result.level = tonumber(child.Value)
                        if result.level then break end
                    end
                end
            end
        end
        local modelKey=farmNameKey(model.Name)
        if modelKey=="npc" or modelKey=="model" or modelKey=="rig" or modelKey:match("^%d+$") then
            result.expires=now+0.4
        end
        farmIdentityCache[model] = result
        return result
    end

    local Catalog = {entries = {}, byId = {}, byKey = {}, labels = {}, resolved = setmetatable({}, {__mode = "k"})}
    World.FarmCatalog = Catalog
    Catalog.islands = {
        {key="starter", name="Foosha Island", aliases={"foosha", "starter"}, point="Starter Island"},
        {key="jungle", name="Jungle Island", aliases={"jungle"}, point="Jungle Island"},
        {key="west", name="West Island", aliases={"westisland", "westcity", "westycity"}, point="West Island"},
        {key="online", name="Online Island", aliases={"onlineisland"}, point="Online Island"},
        {key="sorcerers", name="Sorcerers Island", aliases={"sorcerers", "sorcererisland", "sorceryisland"}, point="Sorcerers Island"},
    }
    Catalog.source = "https://trello.com/b/AODiwMQI/anime-piece-english"
    Catalog.camps = {
        ["starter:0:bandite"] = Vector3.new(488.46, 9.92, -1030.97),
        ["starter:10:monkey"] = Vector3.new(117.64, 10.16, -902.96),
        ["starter:20:higorossbandit"] = Vector3.new(-28.03, 9.92, -1214.83),
        ["jungle:30:monkey"] = Vector3.new(-940.84, 12.36, 23.08),
        ["jungle:45:warriormonkey"] = Vector3.new(-947.14, 11.16, 148.13),
        ["jungle:60:knightmonkey"] = Vector3.new(-1287.41, 11.16, 49.40),
        ["west:75:redbrawler"] = Vector3.new(818.80, 4.73, 2776.29),
        ["west:90:robot"] = Vector3.new(280.58, 10.75, 3225.52),
        ["online:135:corruptedplayer"] = Vector3.new(3772.99, 32.54, 2575.05),
        ["online:150:proplayer"] = Vector3.new(3273.02, 32.54, 2794.87),
        ["sorcerers:165:jujutsustudent"] = Vector3.new(4114.09, 9.45, 4.56),
        ["sorcerers:190:specialstudent"] = Vector3.new(4562.88, 9.45, -53.07),
    }
    local commonMobs = {
        {1,"Bandite",0,{"Bandit"}},
        {1,"Monkey",10},
        {1,"Higoros's Bandit",20,{"Higaro's Bandit","Higaro Bandit","Higoros Bandit"}},
        {2,"Monkey",30},
        {2,"Warrior Monkey",45},
        {2,"Knight Monkey",60},
        {3,"Red Brawler",75},
        {3,"Robot",90},
        {4,"Corrupted Player",135},
        {4,"Pro Player",150},
        {5,"Jujutsu Student",165},
        {5,"Special Student",190},
    }
    Catalog.bossKeys = {}
    for _, name in ipairs({"Higaro","King Monkey","Monkey King","Brawler Chief","Robot King","Robot 15","Robot 16",
        "Crimson King","Frieza","Frieeza","Beast","Broly","Emerald Swordsman","Imperial Pro Player","Dual Swordsman",
        "Kirito","Overtime","Overtime Sorcerer","Panda","White Panda","Itadori","Cursed Prodigy","Prodigy Student","Old Fighter","Master Roshi"}) do
        Catalog.bossKeys[farmNameKey(name)] = true
    end
    for _, data in ipairs(commonMobs) do
        local island = Catalog.islands[data[1]]
        local entry = {island=island, name=data[2], level=data[3], keys={}, order=#Catalog.entries+1, locations={}}
        entry.id = island.key .. ":" .. tostring(entry.level) .. ":" .. farmNameKey(entry.name)
        entry.camp = Catalog.camps[entry.id]
        for _, name in ipairs({entry.name, table.unpack(data[4] or {})}) do
            local key = farmNameKey(name)
            local words=name:lower():gsub("'",""):gsub("’",""):gsub("[^%w]"," "):gsub("%s+"," ")
            Catalog.labels[#Catalog.labels+1]={phrase=words,key=key}
            Catalog.labels[#Catalog.labels+1]={phrase=words.."s",key=key.."s"}
            entry.keys[key], entry.keys[key .. "s"] = true, true
            for _, candidate in ipairs({key,key .. "s"}) do
                Catalog.byKey[candidate] = Catalog.byKey[candidate] or {}
                table.insert(Catalog.byKey[candidate], entry)
            end
        end
        Catalog.entries[#Catalog.entries+1], Catalog.byId[entry.id] = entry, entry
    end

    function Catalog.labelKey(value)
        local raw=tostring(value or ""):gsub("<[^>]*>"," ")
        local key=farmNameKey(raw)
        if Catalog.bossKeys[key] or raw:lower():find("boss",1,true) then return nil,true end
        if Catalog.byKey[key] then return key end
        local cleaned=raw:gsub("%b[]",function(block)
            return block:match("^%[%s*%d+%s*%+?%s*%]$") and " " or block
        end)
        key=farmNameKey(cleaned)
        if Catalog.byKey[key] then return key end
        local base=key:match("^(.-)%d+$")
        if base and Catalog.byKey[base] then return base end
        local words=" "..raw:lower():gsub("'",""):gsub("’",""):gsub("[^%w]"," "):gsub("%s+"," ").." "
        local best,size=nil,0
        local allowed={lv=true,lvl=true,level=true,hp=true,health=true,npc=true,mob=true,enemy=true}
        for _,alias in ipairs(Catalog.labels) do
            local first,last=words:find(" "..alias.phrase.." ",1,true)
            if first and #alias.phrase>size then
                local remainder=words:sub(1,first)..words:sub(last)
                local valid=true
                for word in remainder:gmatch("%a+") do if not allowed[word] then valid=false;break end end
                if valid then best,size=alias.key,#alias.phrase end
            end
        end
        return best
    end

    function Catalog.point(entry)
        local island = entry and (entry.island or entry)
        for _, point in ipairs(World.travelPoints or {}) do
            if island and point.name == island.point then return point end
        end
    end
    function Catalog.islandName(value)
        local key = farmNameKey(value)
        for _, island in ipairs(Catalog.islands) do
            for _, alias in ipairs(island.aliases) do
                if key:find(alias,1,true) then return island end
            end
        end
    end
    function Catalog.islandOf(object)
        local node = object
        while node and node ~= workspace and node ~= game do
            local island = Catalog.islandName(node.Name)
            if island and not node:FindFirstChildOfClass("Humanoid") then return island end
            if World.islands[node] then
                local position=World.islandPosition(node)
                if position then
                    local inferred=Catalog.nearIsland(position)
                    if inferred then return inferred end
                end
            end
            node = node.Parent
        end
    end
    function Catalog.nearIsland(position)
        local first, best, second = nil, math.huge, math.huge
        for _, island in ipairs(Catalog.islands) do
            local point = Catalog.point(island)
            if point then
                local distance = SafeMode.flatDistance(position, point.position)
                if distance < best then first,second,best = island,best,distance
                elseif distance < second then second=distance end
            end
        end
        if best <= 1600 and second - best >= 150 then return first,best end
    end
    function Catalog.boss(model, identity)
        if identity.boss or tostring(identity.name):lower():find("boss",1,true) or tostring(identity.display):lower():find("boss",1,true)
            or identity.keys.boss or identity.keys.miniboss then return true end
        for key in pairs(identity.keys) do if Catalog.bossKeys[key] then return true end end
        local ok, attrs = pcall(function() return model:GetAttributes() end)
        for key,value in pairs(ok and attrs or {}) do
            local field = farmNameKey(key)
            if (field == "isboss" or field == "boss" or field == "isminiboss" or field == "miniboss")
                and value ~= false and value ~= nil and value ~= "" and value ~= 0 then return true end
            if (field == "mobtype" or field == "enemytype" or field == "npctype") and type(value)=="string"
                and value:lower():find("boss",1,true) then return true end
        end
        local service = getServiceSafe("CollectionService")
        local tagged,tags = pcall(function() return service:GetTags(model) end)
        for _,tag in ipairs(tagged and tags or {}) do if farmNameKey(tag):find("boss",1,true) then return true end end
        local parent=model.Parent
        while parent and parent~=workspace and parent~=game do
            local key=farmNameKey(parent.Name)
            if key=="boss" or key=="bosses" or key=="miniboss" or key=="minibosses" or key=="worldbosses" or key=="raidbosses" then return true end
            parent=parent.Parent
        end
        return false
    end
    function Catalog.resolve(model)
        if not model or not model.Parent then return nil end
        local identity=farmIdentity(model)
        if Catalog.boss(model,identity) then return nil end
        local candidates,seen={},{ }
        for key in pairs(identity.keys) do
            for _,entry in ipairs(Catalog.byKey[key] or {}) do
                if not seen[entry] then
                    seen[entry]=true; candidates[#candidates+1]=entry
                end
            end
        end
        if identity.level then
            local matching={}
            for _,entry in ipairs(candidates) do if entry.level==identity.level then matching[#matching+1]=entry end end
            if #matching>0 then candidates=matching end
        end
        local island=Catalog.islandOf(model)
        if not island and #candidates>1 then
            local root=getMobRoot(model)
            if root and model:IsDescendantOf(workspace) then island=Catalog.nearIsland(root.Position) end
        end
        local winner
        for _,entry in ipairs(candidates) do
            if not island or entry.island==island then
                if winner then return nil end
                winner=entry
            end
        end
        return winner
    end
    function Catalog.get(value)
        if Catalog.byId[value] then return Catalog.byId[value] end
        local entries=Catalog.byKey[farmNameKey(value)]
        return entries and #entries==1 and entries[1] or nil
    end
    function Catalog.atIsland(entry, root, target)
        if target then
            local part=getMobRoot(target)
            if part and SafeMode.flatDistance(root.Position,part.Position)<=300 then return true end
        end
        local point=Catalog.point(entry)
        if not point then return false end
        local params=Landing.parameters(LocalPlayer.Character)
        local hit=workspace:Raycast(root.Position+Vector3.new(0,3,0),Vector3.new(0,-70,0),params)
        local currentIsland=hit and hit.Instance and World.islandFor(hit.Instance)
        if currentIsland and target and currentIsland==World.islandFor(target) then return true end
        local land=hit and hit.Material~=Enum.Material.Water and Catalog.islandOf(hit.Instance)
        if land then return land==entry.island end
        local island=Catalog.nearIsland(root.Position)
        return island==entry.island
            or SafeMode.flatDistance(root.Position,point.position)<=450
    end
    function Catalog.destination(entry, root)
        if entry.camp then return entry.camp end
        local position,best=nil,math.huge
        for _,candidate in ipairs(entry.locations) do
            local distance=SafeMode.flatDistance(root.Position,candidate)
            if distance<best then position,best=candidate,distance end
        end
        local point=Catalog.point(entry)
        return position or (point and point.position)
    end

    local function farmMatches(model, name)
        if not model or not model.Parent then return false end
        local selected = Catalog.get(name)
        if selected then return Catalog.resolve(model) == selected end
        local identity = farmIdentity(model)
        local level = farmLevel(name)
        if level and identity.level ~= level then return false end
        return identity.keys[farmNameKey(name)] == true
    end

    local function farmTargetLabel(rawName, level)
        local clean = tostring(rawName or ""):gsub("<[^>]*>", "")
        clean = clean:gsub("%s*%[[Ll][Vv]%.?%s*%d+%s*%]", "")
            :gsub("%s*%[[Ll][Ee][Vv][Ee][Ll]%s*%d+%s*%]", "")
            :gsub("%s+[Ll][Vv][Ll]?%.?%s*%d+%s*$", "")
            :gsub("%s+[Ll][Ee][Vv][Ee][Ll]%s*%d+%s*$", "")
            :gsub("%s+$", "")
        return clean .. " [Lv. " .. tostring(level or "?") .. "]"
    end

    local function rememberFarmMob(model)
        if not model or not model.Parent then return end
        local entry = Catalog.resolve(model)
        local part = getMobRoot(model)
        if not entry or not part then return end
        local identity = farmIdentity(model)
        knownFarmMobNames[entry.id], knownFarmMobSources[model] = true, entry.id
        knownFarmMobLevels[entry.id] = identity.level or entry.level
        local clean = farmTargetLabel(identity.label, identity.level or entry.level):gsub("%s*%[Lv%.%s*%d+%]$", "")
        if clean ~= "" and clean ~= "Humanoid" then entry.displayName = clean end
        knownFarmMobLocations[entry.id] = entry.locations
        for _, old in ipairs(entry.locations) do if (old-part.Position).Magnitude < 180 then return end end
        if #entry.locations < 12 then entry.locations[#entry.locations+1] = part.Position end
    end

    -- Se um personagem antes classificado como mob revelar que e um quest giver,
    -- tire imediatamente a entrada salva da lista. Nao apague mobs homonimos.
    local function forgetFarmMob(model)
        local label = knownFarmMobSources[model]
        if not label then return end
        knownFarmMobSources[model] = nil
        for other, otherLabel in pairs(knownFarmMobSources) do
            if otherLabel == label and other and other.Parent then return end
        end
        knownFarmMobNames[label] = nil
        knownFarmMobLevels[label] = nil
    end

    local searchCooldowns, searchName, nextSearchAt = {}, nil, 0
    local function cancelFarmSearch()
        if knownRegionThread then pcall(task.cancel, knownRegionThread); knownRegionThread = nil end
        World.farmSearchActive = false
    end
    QuestRuntime.StopFarmSearch = cancelFarmSearch

    local function requestKnownMobRegion(name, origin)
        if not workspace.StreamingEnabled or type(LocalPlayer.RequestStreamAroundAsync) ~= "function" then return end
        local entry = Catalog.get(name)
        if not entry or knownRegionThread or Motion.streamPending or Motion.manualThread or World.fruitScanActive
            or QuestRuntime.Interacting or QuestRuntime.ItemBusy then return end
        local now = os.clock()
        if searchName ~= entry.id then searchName,searchCooldowns,nextSearchAt=entry.id,{},0 end
        if now < nextSearchAt then return end
        local points = {}
        local function add(position)
            if not position then return end
            for _,old in ipairs(points) do if (old-position).Magnitude<180 then return end end
            if #points<48 then points[#points+1]=position end
        end
        add(entry.camp)
        for _,position in ipairs(entry.locations) do add(position) end
        local point = Catalog.point(entry)
        if point then add(point.position) end
        if not entry.scanPoints or now >= (entry.nextScanPointsAt or 0) then
            entry.scanPoints,entry.nextScanPointsAt={},now+20
            for island in pairs(World.islands) do
                if island.Parent and Catalog.islandOf(island)==entry.island then
                    local parts=island:GetDescendants()
                    local step=math.max(1,math.ceil(#parts/48))
                    for index=1,#parts,step do
                        local part=parts[index]
                        if part:IsA("BasePart") then entry.scanPoints[#entry.scanPoints+1]=part.Position end
                    end
                end
            end
        end
        for _,position in ipairs(entry.scanPoints) do add(position) end
        local chosen
        for _,position in ipairs(points) do
            local key=math.floor(position.X/180)..":"..math.floor(position.Z/180)
            if now >= (searchCooldowns[key] or 0) then chosen=position;searchCooldowns[key]=now+30;break end
        end
        nextSearchAt=now+2.5
        if not chosen then return end
        local token,handle=autoFarmGeneration,nil
        World.farmSearchActive=true
        handle=task.spawn(function()
            pcall(function() LocalPlayer:RequestStreamAroundAsync(chosen,1.5) end)
            if token~=autoFarmGeneration or destroyed then return end
            knownRegionThread,World.farmSearchActive=nil,false
        end)
        if World.farmSearchActive then knownRegionThread=handle end
    end

    -- Auto Farm selector: index valid mobs across every discoverable island and retain their names/last positions
    -- as regions stream out. No player-distance cap: a selected mob may be on a distant island.
    local FARM_MOB_DETECT_RADIUS = math.huge
    local FARM_MOB_DETECT_RADIUS_SQ = FARM_MOB_DETECT_RADIUS * FARM_MOB_DETECT_RADIUS
    local farmTargetValidation = setmetatable({}, {__mode = "k"})
    -- These are non-combat NPC roles, not mob types. Do not treat every Humanoid as a mob.
    local farmExcludedNameHints = {
        "quest", "npc", "vendor", "merchant", "shopkeeper", "blacksmith", "mission", "trainer",
        "guide", "dealer", "seller", "shop", "gacha", "teleport", "boatman", "craft", "upgrade",
        "daily reward", "quest giver", "questgiver", "fruit dealer", "weapon dealer", "accessory dealer",
        "dialog", "civilian", "villager", "tutorial", "spawnpoint", "dummy", "statue"
    }
    local combatFolderNames = {
        mobs = true, mob = true, mobspawn = true, mobspawns = true,
        enemies = true, enemy = true, enemyspawn = true, enemyspawns = true,
        monsters = true, monster = true, monsterspawns = true,
        bosses = true, boss = true, hostile = true, hostiles = true,
        pirates = true, bandits = true, zombies = true, soldiers = true,
        mobfolder = true, mobmodels = true, enemyfolder = true,
        enemymodels = true, mobsfolder = true, moblocations = true,
        monstersfolder = true, spawnenemies = true, spawnmobs = true,
    }
    local excludedFolderNames = {
        quests = true, quest = true, questgivers = true, questgiver = true,
        questnpcs = true, missionnpcs = true, missiongivers = true,
        merchants = true, vendors = true, shops = true, shop = true,
        trainers = true, dealers = true, dialog = true, dialogues = true,
        interactables = true, civilians = true, players = true, npcs = true,
    }
    local farmCombatNameHints = {
        "bandit", "pirate", "marine", "zombie", "skeleton", "orc", "monster",
        "soldier", "thug", "raider", "enemy", "mob", "boss", "bandido", "inimigo"
    }
    local healthHints = {"health", "hpbar", "hp_bar", "hitpoint", "hit_point", "vida", "life_bar", "lifebar"}
    local function farmCompactName(value)
        return string.lower(tostring(value or "")):gsub("[^%w]", "")
    end
    local function farmExcludedName(value)
        local name = string.lower(tostring(value or ""))
        for _, hint in ipairs(farmExcludedNameHints) do
            if name:find(hint, 1, true) then return true end
        end
        return false
    end
    local function farmCombatContext(object, stopAt)
        local combat, excluded = false, false
        local node = object and object.Parent
        while node and node ~= stopAt and node ~= game do
            local compact = farmCompactName(node.Name)
            if excludedFolderNames[compact] then excluded = true end
            if combatFolderNames[compact] then combat = true end
            node = node.Parent
        end
        return combat and not excluded
    end
    local function farmHasCombatName(name)
        local lower = string.lower(tostring(name or ""))
        for _, hint in ipairs(farmCombatNameHints) do
            if lower:find(hint, 1, true) then return true end
        end
        return false
    end
    local CollectionService = game:GetService("CollectionService")
    local function farmTaggedEnemy(object)
        local ok, tags = pcall(function() return CollectionService:GetTags(object) end)
        if not ok then return false, false end
        local hostile, nonCombat = false, false
        for _, tag in ipairs(tags) do
            local name = farmCompactName(tag)
            if combatFolderNames[name] or name == "ismob" or name == "isenemy" then hostile = true end
            if excludedFolderNames[name] or name == "isquestgiver" or name == "questnpc"
                or name == "isquestnpc" or name == "givesquest" or name == "missiongiver"
                or name == "vendor" or name == "merchant" or name == "isvendor"
                or name == "ismerchant" or name == "istrainer" then nonCombat = true end
        end
        return hostile, nonCombat
    end
    local function farmMarkedEnemy(attributes)
        for key, value in pairs(attributes) do
            local field = farmCompactName(key)
            local valueKey = type(value) == "string" and farmCompactName(value) or ""
            local enabled = value == true or (type(value) == "number" and value > 0)
                or (valueKey ~= "" and valueKey ~= "false" and valueKey ~= "none" and valueKey ~= "nil" and valueKey ~= "0")
            if (field == "questgiver" or field == "isquestgiver"
                or field == "questnpc" or field == "isquestnpc" or field == "merchant"
                or field == "vendor" or field == "isvendor" or field == "ismerchant"
                or field == "shop" or field == "isshop" or field == "trainer" or field == "istrainer"
                or field == "givesquest" or field == "givesquests"
                or field == "providesquest" or field == "providesquests"
                or field == "missiongiver") and enabled then
                return false, true
            end
        end
        for key, value in pairs(attributes) do
            local field = farmCompactName(key)
            if (field == "ismob" or field == "isenemy" or field == "mobtype"
                or field == "enemytype" or field == "isboss" or field == "monster")
                and value ~= nil and value ~= false and value ~= "" then
                return true, false
            end
        end
        return false, false
    end

    -- O Select Target so aceita mobs de combate. Level/barra de vida por si so
    -- nao bastam: muitos NPCs de quest tambem possuem ambos.
    local function farmQuestGiver(model, knownOnly)
        -- Reutiliza o catalogo da aba de quest para que o mesmo NPC nunca apareca
        -- simultaneamente como "Select Quest NPC" e como alvo do Auto Farm.
        for _, entries in ipairs({AcceptQuest.entries or {}, AcceptQuest.knownEntries or {}}) do
            for _, entry in pairs(entries) do
                if entry.model == model then return true end
            end
        end
        if knownOnly then return false end
        if type(AcceptQuest.metadata) == "function" then
            local ok, evidence = pcall(AcceptQuest.metadata, model)
            if ok and evidence and evidence.quest and not evidence.enemy then return true end
        end
        return false
    end

    local function farmNonCombatFolder(model)
        local inNpcFolder, inQuestFolder, roleFolder = false, false, false
        local node = model.Parent
        while node and node ~= workspace and node ~= game do
            local key = farmCompactName(node.Name)
            if key:find("questgiver", 1, true) or key:find("questnpc", 1, true)
                or key:find("missiongiver", 1, true) or key:find("missionnpc", 1, true)
                or key == "quest" or key == "quests" then
                inQuestFolder = true
            elseif excludedFolderNames[key] then
                inNpcFolder = true
                if key~="npcs" then roleFolder=true end
            end
            node = node.Parent
        end
        return inNpcFolder, inQuestFolder, roleFolder
    end

    local function isFarmTargetMob(model)
        if not World.liveMob(model) or (farmExcludedName(model.Name) and not Catalog.resolve(model)) or farmQuestGiver(model) then
            forgetFarmMob(model)
            return false
        end
        local now = os.clock()
        local cached = farmTargetValidation[model]
        if cached and now < cached.expires then return cached.valid end

        local okAttrs, attrs = pcall(function() return model:GetAttributes() end)
        local markedEnemy, explicitNpc = farmMarkedEnemy(okAttrs and attrs or {})
        local taggedEnemy, taggedNpc = farmTaggedEnemy(model)
        if explicitNpc or taggedNpc then
            farmTargetValidation[model] = {valid = false, expires = now + 6}
            forgetFarmMob(model)
            return false
        end
        local humanoid = getMobHumanoid(model)
        local inNpcFolder, inQuestFolder, roleFolder = farmNonCombatFolder(model)
        if inQuestFolder or roleFolder or (inNpcFolder and not markedEnemy and not taggedEnemy and not Catalog.resolve(model)) then
            farmTargetValidation[model] = {valid = false, expires = now + 4}
            forgetFarmMob(model)
            return false
        end
        local hasHealthBar, hasInteraction = false, false
        -- Scan the model only once. Interaction NPCs are rejected even if they have Humanoids.
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
                hasInteraction = true
                break
            end
            local board = object:IsA("BillboardGui") and object or object:FindFirstAncestorWhichIsA("BillboardGui")
            if board then
                local lower = string.lower(object.Name)
                if object:IsA("TextLabel") then lower = lower .. " " .. string.lower(object.Text) end
                for _, hint in ipairs(healthHints) do
                    if lower:find(hint, 1, true) then hasHealthBar = true; break end
                end
                if lower:match("%d+%s*/%s*%d+") or lower:match("%d+%%") then hasHealthBar = true end
            end
        end
        if hasInteraction then
            farmTargetValidation[model] = {valid = false, expires = now + 5}
            forgetFarmMob(model)
            return false
        end
        local lowerName = string.lower(model.Name)
        local levelInName = lowerName:match("lv%.?%s*%d+") or lowerName:match("level%s*%d+")
            or lowerName:match("%[%s*%d+%s*%]")
        local combatContext = farmCombatContext(model, workspace)
        local healthInCombat = humanoid and humanoid.MaxHealth > 0
            and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth
            and humanoid.HealthDisplayDistance > 0
            and humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None
        -- A regular humanoid's native health display alone does not prove it is a mob.
        local valid = Catalog.resolve(model) ~= nil or markedEnemy or taggedEnemy or combatContext or levelInName ~= nil
            or hasHealthBar or healthInCombat or farmHasCombatName(model.Name)
        farmTargetValidation[model] = {valid = valid == true, expires = now + (valid and 10 or 4)}
        return valid == true
    end

    isValidFarmMob = isFarmTargetMob

    collectFarmMobTypes = function()
        for humanoid in pairs(World.humanoids) do
            local model=humanoid.Parent
            if model and Catalog.resolve(model) and isFarmTargetMob(model) then rememberFarmMob(model) end
        end
        local result={}
        for _,entry in ipairs(Catalog.entries) do result[#result+1]=entry.id end
        return result
    end

    local function findNearestFarmMob(origin, targetName)
        if type(targetName) ~= "string" or targetName == "" or not origin then return nil end
        local best, bestDistanceSquared = nil, math.huge
        local originPosition = origin.Position
        for humanoid in pairs(World.humanoids) do
            local model = humanoid.Parent
            if model and model.Parent and farmMatches(model,targetName) then
                local mobRoot = getMobRoot(model)
                if mobRoot then
                    local offset = mobRoot.Position - originPosition
                    local distanceSquared = offset:Dot(offset)
                    if distanceSquared <= FARM_MOB_DETECT_RADIUS_SQ
                        and distanceSquared < bestDistanceSquared
                        and os.clock() >= (Motion.blocked[model] or 0)
                        and isFarmTargetMob(model) then
                        best, bestDistanceSquared = model, distanceSquared
                    end
                end
            end
        end
        if best then rememberFarmMob(best) end
        return best
    end

    local function getSelectedFarmMobIndex(name)
        for index, selectedName in ipairs(selectedFarmMobNames) do
            if selectedName == name then return index end
        end
        return nil
    end

    local function getCurrentFarmMobName()
        if #selectedFarmMobNames == 0 then
            currentFarmMobIndex = 1
            return nil
        end
        if currentFarmMobIndex < 1 or currentFarmMobIndex > #selectedFarmMobNames then
            currentFarmMobIndex = 1
        end
        return selectedFarmMobNames[currentFarmMobIndex]
    end

    World.onFarmMobRemoved = function(object)
        if autoFarmEnabled and farmTarget and object:IsA("Humanoid") and object.Parent==farmTarget and object.Health<=0 then farmKilledCurrent=true end
    end

    local function advanceFarmMobQueue()
        farmKilledCurrent=false
        if #selectedFarmMobNames == 0 then
            currentFarmMobIndex = 1
        else
            currentFarmMobIndex = (currentFarmMobIndex % #selectedFarmMobNames) + 1
        end
        farmTarget = nil
    end

    local function farmSelectorDisplayName(name)
        local entry=Catalog.get(name)
        if entry then return farmTargetLabel(entry.displayName or entry.name,knownFarmMobLevels[entry.id] or entry.level) end
        return tostring(name)
    end

    -- Identical surface, typography and colors to TP Island's dropdown.
    local farmPalette = {
        surface = Color3.fromRGB(30, 30, 33),
        input = Color3.fromRGB(39, 39, 42),
        list = Color3.fromRGB(21, 21, 24),
        text = Color3.fromRGB(245, 245, 250),
        muted = Color3.fromRGB(174, 178, 191),
    }

    local function updateFarmSelectionText()
        if not FarmSelectionButton or not FarmSelectionButton.Parent then return end
        if #selectedFarmMobNames == 0 then
            FarmSelectionButton.Text = "Select Mob"
        elseif #selectedFarmMobNames == 1 then
            local entry=Catalog.get(selectedFarmMobNames[1])
            FarmSelectionButton.Text = (entry and entry.island.name .. " · " or "") .. farmSelectorDisplayName(selectedFarmMobNames[1])
        else
            FarmSelectionButton.Text = tostring(#selectedFarmMobNames) .. " Mobs Selected"
        end
    end

    local function updateFarmMobRowStyles()
        for name, row in pairs(farmMobRowButtons) do
            if row and row.Parent then
                local selectedIndex = getSelectedFarmMobIndex(name)
                local selected = selectedIndex ~= nil
                row.BackgroundColor3 = selected and Theme.Accent2 or farmPalette.input
                row.TextColor3 = selected and farmPalette.text or farmPalette.muted
                row.Text = selected and ("✓  " .. tostring(selectedIndex) .. ". " .. farmSelectorDisplayName(name)) or farmSelectorDisplayName(name)
            end
        end
        updateFarmSelectionText()
    end

    local function rebuildFarmMobRows(names)
        for _, connection in ipairs(farmMobRowConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(farmMobRowConnections)
        for _, child in ipairs(FarmMobList:GetChildren()) do
            if child:IsA("TextButton") or child.Name == "EmptyMessage" or child.Name:match("^IslandHeader_") then
                child:Destroy()
            end
        end
        table.clear(farmMobRowButtons)
        renderedFarmMobNames = table.clone(names)

        if #names == 0 then
            local empty = Instance.new("TextLabel")
            empty.Name = "EmptyMessage"
            empty.Size = UDim2.new(1, -6, 0, 33)
            empty.BackgroundColor3 = farmPalette.input
            empty.BorderSizePixel = 0
            empty.Text = "No targets found"
            empty.TextColor3 = farmPalette.muted
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.ZIndex = 17
            empty.Parent = FarmMobList
            addCorner(empty, 7)
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 12)
            pad.Parent = empty
            FarmMobList.CanvasPosition = Vector2.new(0, 0)
            return
        end

        local previousIsland,layoutOrder=nil,0
        for index, name in ipairs(names) do
            local entry=Catalog.get(name)
            if entry and entry.island~=previousIsland then
                previousIsland=entry.island
                layoutOrder=layoutOrder+1
                local heading=Instance.new("TextLabel")
                heading.Name="IslandHeader_"..entry.island.key
                heading.Size=UDim2.new(1,-6,0,25)
                heading.BackgroundTransparency=1
                heading.Text=entry.island.name
                heading.TextColor3=farmPalette.muted
                heading.Font=Enum.Font.GothamBold
                heading.TextSize=12
                heading.TextXAlignment=Enum.TextXAlignment.Left
                heading.LayoutOrder,heading.ZIndex=layoutOrder,17
                heading.Parent=FarmMobList
            end
            layoutOrder=layoutOrder+1
            local selectedIndex = getSelectedFarmMobIndex(name)
            local selected = selectedIndex ~= nil
            local row = Instance.new("TextButton")
            row.Name = "MobTarget_" .. tostring(index)
            row.Size = UDim2.new(1, -6, 0, 33)
            row.BackgroundColor3 = selected and Theme.Accent2 or farmPalette.input
            row.BorderSizePixel = 0
            row.AutoButtonColor = true
            row.Text = selected and ("✓  " .. tostring(selectedIndex) .. ". " .. farmSelectorDisplayName(name)) or farmSelectorDisplayName(name)
            row.TextColor3 = selected and farmPalette.text or farmPalette.muted
            row.TextSize = 12
            row.Font = Enum.Font.Gotham
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.LayoutOrder = layoutOrder
            if entry then row:SetAttribute("MobId",entry.id);row:SetAttribute("Island",entry.island.name);row:SetAttribute("MobName",entry.name) end
            row.ZIndex = 17
            row.Parent = FarmMobList
            addCorner(row, 7)
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 12)
            pad.Parent = row
            farmMobRowButtons[name] = row
            local rowConnection = row.MouseButton1Click:Connect(function()
                if destroyed then return end
                local selectedIndexNow = getSelectedFarmMobIndex(name)
                if selectedIndexNow then
                    table.remove(selectedFarmMobNames, selectedIndexNow)
                    if selectedIndexNow < currentFarmMobIndex then
                        currentFarmMobIndex = currentFarmMobIndex - 1
                    elseif selectedIndexNow == currentFarmMobIndex then
                        farmTarget = nil
                        if currentFarmMobIndex > #selectedFarmMobNames then
                            currentFarmMobIndex = 1
                        end
                    end
                else
                    table.insert(selectedFarmMobNames, name)
                end

                if #selectedFarmMobNames == 0 then
                    currentFarmMobIndex = 1
                    farmTarget = nil
                elseif currentFarmMobIndex > #selectedFarmMobNames then
                    currentFarmMobIndex = 1
                end

                farmKilledCurrent=false
                updateFarmMobRowStyles()
                -- Keep the dropdown open for multi-selection. Tap Select Target to close it.
                -- Once the player picks the quest mob, allow Auto Farm to move.
                -- The active quest remains locked: do not walk back to its NPC.
                QuestRuntime.HasFarmSelection = #selectedFarmMobNames > 0
                if QuestRuntime.HasFarmSelection then
                    QuestRuntime.WaitForFarmSelection = false
                end
                if autoFarmEnabled then
                    if #selectedFarmMobNames == 0 or not autoFarmThread then
                        startAutoFarm(false)
                    end
                end
            end)
            table.insert(farmMobRowConnections, rowConnection)
        end
    end

    refreshFarmMobTypes = function(force)
        if destroyed or not FarmMobList then return end
        local names = collectFarmMobTypes()
        local changed = #names ~= #renderedFarmMobNames
        if not changed then
            for i, name in ipairs(names) do
                if renderedFarmMobNames[i] ~= name then changed = true break end
            end
        end
        if changed or force or not farmMobListInitialized then
            rebuildFarmMobRows(names)
            farmMobListInitialized = true
        else
            updateFarmMobRowStyles()
        end
    end

    -- TP Island-style selector; only the labels and target-selection action differ.
    local FarmTargetCard = createStyledCard(AutoFarmPage, "FarmTargetSelectorCard", 96, 4)
    -- Match the Auto Farm / Auto World Boss toggles' gray background and gradient.
    FarmTargetCard.BackgroundColor3 = AutoFarmCard.BackgroundColor3
    FarmTargetCard.ZIndex = 4
    local FarmTargetTitle = Instance.new("TextLabel")
    FarmTargetTitle.Name = "FarmTargetTitle"
    FarmTargetTitle.Size = UDim2.new(1, -20, 0, 25)
    FarmTargetTitle.Position = UDim2.fromOffset(10, 8)
    FarmTargetTitle.BackgroundTransparency = 1
    FarmTargetTitle.Text = "Select Mob"
    FarmTargetTitle.TextColor3 = farmPalette.text
    FarmTargetTitle.TextSize = 18
    FarmTargetTitle.Font = Enum.Font.GothamBold
    FarmTargetTitle.TextXAlignment = Enum.TextXAlignment.Left
    FarmTargetTitle.Parent = FarmTargetCard

    FarmSelectionButton = Instance.new("TextButton")
    FarmSelectionButton.Name = "SelectTarget"
    FarmSelectionButton.Size = UDim2.new(1, -16, 0, 36)
    FarmSelectionButton.Position = UDim2.fromOffset(8, 42)
    FarmSelectionButton.BackgroundColor3 = farmPalette.input
    FarmSelectionButton.BorderSizePixel = 0
    FarmSelectionButton.Text = "Select Mob"
    FarmSelectionButton.Font = Enum.Font.Gotham
    FarmSelectionButton.TextSize = 13
    FarmSelectionButton.TextColor3 = farmPalette.text
    FarmSelectionButton.TextXAlignment = Enum.TextXAlignment.Left
    FarmSelectionButton.TextTruncate = Enum.TextTruncate.AtEnd
    FarmSelectionButton.AutoButtonColor = true
    FarmSelectionButton.ZIndex = 6
    FarmSelectionButton.Parent = FarmTargetCard
    addCorner(FarmSelectionButton, 9)
    local selectionPadding = Instance.new("UIPadding")
    selectionPadding.PaddingLeft = UDim.new(0, 12)
    selectionPadding.PaddingRight = UDim.new(0, 12)
    selectionPadding.Parent = FarmSelectionButton

    local ClearTargetButton = Instance.new("TextButton")
    ClearTargetButton.Name = "ClearTarget"
    ClearTargetButton.Size = UDim2.new(1, -12, 0, 32)
    ClearTargetButton.Position = UDim2.fromOffset(6, 6)
    ClearTargetButton.BackgroundColor3 = farmPalette.input
    ClearTargetButton.BorderSizePixel = 0
    ClearTargetButton.AutoButtonColor = true
    ClearTargetButton.Font = Enum.Font.Gotham
    ClearTargetButton.TextSize = 12
    ClearTargetButton.TextColor3 = farmPalette.text
    ClearTargetButton.Text = "Clear Selection"
    ClearTargetButton.ZIndex = 17
    ClearTargetButton.Parent = FarmTargetCard
    addCorner(ClearTargetButton, 9)
    connect(ClearTargetButton.MouseButton1Click, function()
        if destroyed then return end
        table.clear(selectedFarmMobNames)
        QuestRuntime.HasFarmSelection = false
        currentFarmMobIndex = 1
        farmTarget = nil
        if FarmTargetDropdown then FarmTargetDropdown.Visible = false end
        if refreshFarmMobTypes then refreshFarmMobTypes(true) end
        updateFarmSelectionText()
        if autoFarmEnabled then startAutoFarm(false) end
    end)

    FarmTargetDropdown = Instance.new("Frame")
    FarmTargetDropdown.Name = "TargetDropdown"
    FarmTargetDropdown.Size = UDim2.new(1, -16, 0, 215)
    FarmTargetDropdown.Position = UDim2.fromOffset(8, 80)
    FarmTargetDropdown.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    FarmTargetDropdown.BorderSizePixel = 0
    FarmTargetDropdown.ZIndex = 15
    FarmTargetDropdown.Visible = false
    FarmTargetDropdown.Parent = FarmTargetCard
    addCorner(FarmTargetDropdown, 9)
    addStroke(FarmTargetDropdown, Color3.fromRGB(66, 67, 79), 1, 0.1)
    -- Keep Clear Selection in the dropdown so the selector card matches the boss selectors.
    ClearTargetButton.Parent = FarmTargetDropdown

    FarmMobList = Instance.new("ScrollingFrame")
    FarmMobList.Name = "TargetChoices"
    FarmMobList.Size = UDim2.new(1, -12, 1, -51)
    FarmMobList.Position = UDim2.fromOffset(6, 45)
    FarmMobList.BackgroundTransparency = 1
    FarmMobList.BorderSizePixel = 0
    FarmMobList.ScrollBarThickness = 4
    FarmMobList.ScrollBarImageColor3 = Color3.fromRGB(59, 94, 198)
    FarmMobList.ScrollingDirection = Enum.ScrollingDirection.Y
    FarmMobList.CanvasSize = UDim2.fromOffset(0, 0)
    FarmMobList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    FarmMobList.ZIndex = 16
    FarmMobList.Parent = FarmTargetDropdown
    local FarmMobListLayout = Instance.new("UIListLayout")
    FarmMobListLayout.Padding = UDim.new(0, 5)
    FarmMobListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    FarmMobListLayout.Parent = FarmMobList

    connect(FarmSelectionButton.MouseButton1Click, function()
        if destroyed then return end
        local open = not FarmTargetDropdown.Visible
        if open and refreshFarmMobTypes then refreshFarmMobTypes(true) end
        if open and closeMiniBossDropdown then closeMiniBossDropdown() end
        FarmTargetDropdown.Visible = open
    end)
    updateFarmSelectionText()

    local function renderFarmToggle()
        FarmToggleGradient.Color = autoFarmEnabled and TOGGLE_ON or TOGGLE_OFF
        FarmToggleStroke.Transparency = autoFarmEnabled and 0.6 or 0.3
        tween(FarmToggleKnob, {
            Position = autoFarmEnabled and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11),
        }, 0.18)
    end

    startAutoFarm = function(resetQueue)
        if stopMiniBoss then stopMiniBoss() end
        if WorldBoss.Enabled and type(WorldBoss.Stop) == "function" then WorldBoss.Stop() end
        cancelFarmSearch()
        Motion.release("Farm")
        autoFarmGeneration = autoFarmGeneration + 1
        local token = autoFarmGeneration
        autoFarmEnabled = true
        QuestRuntime.AutoFarmEnabled = true
        farmKilledCurrent=false
        if resetQueue ~= false then
            currentFarmMobIndex = 1
        end
        if #selectedFarmMobNames == 0 then
            currentFarmMobIndex = 1
        elseif currentFarmMobIndex < 1 or currentFarmMobIndex > #selectedFarmMobNames then
            currentFarmMobIndex = 1
        end
        renderFarmToggle()
        if autoFarmThread then pcall(task.cancel, autoFarmThread) end
        autoFarmThread = nil
        if #selectedFarmMobNames == 0 then
            return
        end

        local threadHandle
        local lastFarmError = -math.huge
        threadHandle = task.spawn(function()
            while not destroyed and autoFarmEnabled and autoFarmGeneration == token do
                local ok, err = pcall(function()
                if autoQuestEnabled or not Motion.allowed("Farm") then
                    cancelFarmSearch()
                    Motion.release("Farm")
                    task.wait(0.5)
                elseif #selectedFarmMobNames == 0 then
                    farmTarget = nil
                    task.wait(0.25)
                else
                    local character = LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
                        farmTarget = nil
                        setFarmStatus("Waiting for character/respawn...")
                        task.wait(0.25)
                    else
                        local currentName = getCurrentFarmMobName()
                        local target = farmTarget

                        if target then
                            local targetHumanoid = getMobHumanoid(target)
                            if targetHumanoid and targetHumanoid.Health<=0 then farmKilledCurrent=true end
                            local targetGone = not target.Parent or not target:IsDescendantOf(workspace)
                            local targetDead = not targetHumanoid or targetHumanoid.Health <= 0
                            if not farmMatches(target,currentName) then
                                target = nil
                                farmTarget = nil
                            elseif targetGone or targetDead then
                                -- Keep this selected type until no live mobs of that type remain.
                                -- The next search checks currentName before trying another type.
                                farmTarget = nil
                                target = nil
                            else
                                local currentRoot = getMobRoot(target)
                                local offset = currentRoot and (currentRoot.Position - root.Position)
                                local outsideDetectionRange = not offset or offset:Dot(offset) > FARM_MOB_DETECT_RADIUS_SQ
                                if outsideDetectionRange or not isFarmTargetMob(target) then
                                    target = nil
                                    farmTarget = nil
                                end
                            end
                        end

                        if not target then
                            currentName = getCurrentFarmMobName()
                            target = findNearestFarmMob(root, currentName)
                            farmTarget = target
                        end

                        if not target and farmKilledCurrent and #selectedFarmMobNames>1 then
                            advanceFarmMobQueue()
                            currentName=getCurrentFarmMobName()
                            target=findNearestFarmMob(root,currentName)
                            farmTarget=target
                        end
                        local entry=Catalog.get(currentName)
                        local islandPoint=Catalog.point(entry)
                        if entry and islandPoint and not Catalog.atIsland(entry,root,target) then
                            Motion.request("Farm",nil,0,"point",islandPoint.position)
                            requestKnownMobRegion(currentName,root)
                            task.wait(0.25)
                            return
                        end
                        if not target then
                            local destination, nearest = nil, math.huge
                            destination=entry and Catalog.destination(entry,root)
                            if destination then nearest=SafeMode.flatDistance(root.Position,destination) end
                            local arrivalRange=entry and entry.camp and 3 or 20
                            local travelling=destination and nearest>arrivalRange
                            if travelling then Motion.request("Farm",nil,0,"point",destination)
                            else Motion.release("Farm") end
                            requestKnownMobRegion(currentName, root)
                            task.wait(travelling and 0.2 or 0.6)
                        else
                            local targetHumanoid = getMobHumanoid(target)
                            local targetRoot = getMobRoot(target)
                            if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot then
                                -- A single kill does not advance the selected-type queue.
                                -- Another living mob of the same type has priority.
                                farmTarget = nil
                                task.wait(0.1)
                            else
                                cancelFarmSearch()
                                Motion.request("Farm", target, math.clamp(tonumber(farmDistance) or 1, 1, 10), "mob")
                                task.wait(0.2)
                            end
                        end
                    end
                end
                end)
                if not ok then
                    farmTarget = nil
                    cancelFarmSearch()
                    Motion.release("Farm")
                    if os.clock()-lastFarmError >= 8 then warn("[Random Hub | Auto Farm] " .. tostring(err)); lastFarmError=os.clock() end
                    task.wait(0.5)
                end
            end
            if autoFarmThread == threadHandle then autoFarmThread = nil end
        end)
        autoFarmThread = threadHandle
    end

    local function disableAutoFarm()
        Motion.release("Farm")
        autoFarmGeneration = autoFarmGeneration + 1
        autoFarmEnabled = false
        QuestRuntime.AutoFarmEnabled = false
        farmTarget = nil
        local thread = autoFarmThread
        autoFarmThread = nil
        if thread then pcall(task.cancel, thread) end
        cancelFarmSearch()
        renderFarmToggle()
        setFarmStatus("Disabled")
    end
    stopAutoFarm = disableAutoFarm

    connect(FarmToggle.MouseButton1Click, function()
        if autoFarmEnabled then disableAutoFarm() else startAutoFarm(true) end
    end)

    -- AUTO MINI BOSS — manual catalog. Do not auto-populate the selector from Workspace.
    -- Order in the dropdown: level ascending; travel order: the order selected by the user.
    do
        local miniBossCatalog = {
            {name = "Higaro", level = 40, position = Vector3.new(161.94, 34.37, -1531.20)},
            {name = "King Monkey", level = 70, position = Vector3.new(-1176.97, 36.48, -145.85)},
            {name = "Brawler Chief", level = 80, position = Vector3.new(816.61, 23.94, 2779.90)},
            {name = "Robot King", level = 105, position = Vector3.new(304.45, 45.54, 3293.37)},
            {name = "Robot 15", level = 115, position = Vector3.new(1215.83, 22.24, 3586.59)},
            {name = "Robot 16", level = 115, position = Vector3.new(1215.83, 22.24, 3586.59)},
            {name = "Crimson King", level = 120, position = WorldBoss.DropCamps["Crimson King"]},
            {name = "Frieza", level = 130, position = Vector3.new(1225.69, 29.45, 2788.45)},
            {name = "Emerald Swordsman", level = 150, position = Vector3.new(3791.40, 41.83, 2575.56)},
            {name = "Imperial Pro Player", level = 175, position = Vector3.new(3271.78, 48.42, 2785.84)},
            {name = "Old Fighter", level = 200, aliases = {"Master Roshi"}, island = "Good House", islandFallback = true, dynamic = true},
            {name = "White Panda", level = 225, position = Vector3.new(4666.56, 16.12, 225.38)},
        }
        local miniByName = {}
        for _, entry in ipairs(miniBossCatalog) do
            if entry.islandFallback then
                for _,point in ipairs(World.travelPoints or {}) do
                    if point.name==entry.island then entry.position=point.position;break end
                end
            end
            miniByName[entry.name] = entry
        end
        WorldBoss.MiniCamps = miniByName

        local miniBossEnabled = false
        local miniSelected = {}             -- checked entries, keyed by stable boss name
        local miniSelectionOrder = {}       -- first checked, first visited
        local miniSelectionVersion = 0
        local miniBossToken = 0
        local miniBossThread = nil
        local miniTarget = nil
        local miniLastWarning = -math.huge
        WorldBoss.IsMiniTarget = function(model) return miniBossEnabled and miniTarget==model end
        local MINI_SEARCH_RADIUS = 250
        local miniNameCache = setmetatable({}, {__mode = "k"})

        local MiniToggleCard = createStyledCard(AutoFarmPage, "AutoMiniBossToggleCard", 52, 5)
        local MiniTitle = Instance.new("TextLabel")
        MiniTitle.Name = "AutoMiniBossTitle"
        MiniTitle.Size = UDim2.new(1, -100, 0, 26)
        MiniTitle.Position = UDim2.fromOffset(16, 11)
        MiniTitle.BackgroundTransparency = 1
        MiniTitle.Text = "Auto Mini Boss"
        MiniTitle.TextColor3 = Theme.Text
        MiniTitle.Font = Enum.Font.GothamBold
        MiniTitle.TextSize = 15
        MiniTitle.TextXAlignment = Enum.TextXAlignment.Left
        MiniTitle.Parent = MiniToggleCard

        local MiniToggle = Instance.new("TextButton")
        MiniToggle.Name = "AutoMiniBossToggle"
        MiniToggle.Size = UDim2.fromOffset(52, 28)
        MiniToggle.Position = UDim2.new(1, -68, 0, 11)
        MiniToggle.BackgroundColor3 = Color3.new(1, 1, 1)
        MiniToggle.BorderSizePixel = 0
        MiniToggle.Text = ""
        MiniToggle.AutoButtonColor = false
        MiniToggle.Parent = MiniToggleCard
        addCorner(MiniToggle, 14)
        local MiniStroke = addStroke(MiniToggle, Theme.Stroke, 1, 0.3)
        local MiniGradient = Instance.new("UIGradient")
        MiniGradient.Color = TOGGLE_OFF
        MiniGradient.Parent = MiniToggle
        local MiniKnob = Instance.new("Frame")
        MiniKnob.Name = "Knob"
        MiniKnob.Size = UDim2.fromOffset(22, 22)
        MiniKnob.Position = UDim2.new(0, 3, 0.5, -11)
        MiniKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        MiniKnob.BorderSizePixel = 0
        MiniKnob.Parent = MiniToggle
        addCorner(MiniKnob, 11)

        local MiniCard = createStyledCard(AutoFarmPage, "MiniBossSelectorCard", 96, 6)
        MiniCard.BackgroundColor3 = MiniToggleCard.BackgroundColor3
        MiniCard.ZIndex = 3
        local MiniSelectTitle = Instance.new("TextLabel")
        MiniSelectTitle.Name = "MiniBossSectionTitle"
        MiniSelectTitle.Size = UDim2.new(1, -20, 0, 25)
        MiniSelectTitle.Position = UDim2.fromOffset(10, 8)
        MiniSelectTitle.BackgroundTransparency = 1
        MiniSelectTitle.Text = "Select Mini Boss"
        MiniSelectTitle.TextColor3 = farmPalette.text
        MiniSelectTitle.Font = Enum.Font.GothamBold
        MiniSelectTitle.TextSize = 18
        MiniSelectTitle.TextXAlignment = Enum.TextXAlignment.Left
        MiniSelectTitle.Parent = MiniCard

        local MiniSelectButton = Instance.new("TextButton")
        MiniSelectButton.Name = "SelectMiniBoss"
        MiniSelectButton.Size = UDim2.new(1, -16, 0, 36)
        MiniSelectButton.Position = UDim2.fromOffset(8, 42)
        MiniSelectButton.BackgroundColor3 = farmPalette.input
        MiniSelectButton.BorderSizePixel = 0
        MiniSelectButton.Text = "Select Mini Boss"
        MiniSelectButton.Font = Enum.Font.Gotham
        MiniSelectButton.TextSize = 13
        MiniSelectButton.TextColor3 = farmPalette.text
        MiniSelectButton.TextXAlignment = Enum.TextXAlignment.Left
        MiniSelectButton.AutoButtonColor = true
        MiniSelectButton.ZIndex = 6
        MiniSelectButton.Parent = MiniCard
        addCorner(MiniSelectButton, 9)
        local MiniSelectPad = Instance.new("UIPadding")
        MiniSelectPad.PaddingLeft = UDim.new(0, 12)
        MiniSelectPad.PaddingRight = UDim.new(0, 12)
        MiniSelectPad.Parent = MiniSelectButton

        -- Expanding the actual card reflows the other sections and keeps the dropdown
        -- reachable through the Auto Farm page's own scroll bar.
        MiniBossDropdown = Instance.new("Frame")
        MiniBossDropdown.Name = "MiniBossDropdown"
        MiniBossDropdown.Size = UDim2.new(1, -16, 0, 238)
        MiniBossDropdown.Position = UDim2.fromOffset(8, 80)
        MiniBossDropdown.BackgroundColor3 = Theme.Card
        MiniBossDropdown.BorderSizePixel = 0
        MiniBossDropdown.ZIndex = 15
        MiniBossDropdown.Visible = false
        MiniBossDropdown.Parent = MiniCard
        closeMiniBossDropdown = function()
            MiniBossDropdown.Visible = false
            MiniCard.Size = UDim2.new(1, 0, 0, 96)
        end
        addCorner(MiniBossDropdown, 9)
        addStroke(MiniBossDropdown, Color3.fromRGB(66, 67, 79), 1, 0.1)

        local miniList = Instance.new("ScrollingFrame")
        miniList.Name = "MiniBossChoices"
        miniList.Position = UDim2.fromOffset(6, 6)
        miniList.Size = UDim2.new(1, -12, 1, -12)
        miniList.BackgroundTransparency = 1
        miniList.BorderSizePixel = 0
        miniList.ScrollingDirection = Enum.ScrollingDirection.Y
        miniList.ScrollBarThickness = 4
        miniList.ScrollBarImageColor3 = Theme.Accent2
        miniList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        miniList.CanvasSize = UDim2.fromOffset(0, 0)
        miniList.ZIndex = 16
        miniList.Parent = MiniBossDropdown
        local miniLayout = Instance.new("UIListLayout")
        miniLayout.Padding = UDim.new(0, 5)
        miniLayout.SortOrder = Enum.SortOrder.LayoutOrder
        miniLayout.Parent = miniList
        local miniListPad = Instance.new("UIPadding")
        miniListPad.PaddingBottom = UDim.new(0, 4)
        miniListPad.Parent = miniList

        local miniRows = {}
        for index, entry in ipairs(miniBossCatalog) do
            local row = Instance.new("TextButton")
            row.Name = "MiniBoss_" .. entry.name:gsub("%W", "")
            row.Size = UDim2.new(1, -7, 0, 34)
            row.LayoutOrder = index
            row.BackgroundColor3 = farmPalette.input
            row.BorderSizePixel = 0
            row.AutoButtonColor = true
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.TextColor3 = farmPalette.text
            row.TextSize = 12
            row.Font = Enum.Font.Gotham
            row.ZIndex = 17
            row.Parent = miniList
            addCorner(row, 7)
            local inset = Instance.new("UIPadding")
            inset.PaddingLeft = UDim.new(0, 10)
            inset.Parent = row
            miniRows[entry.name] = row
        end

        local function renderMini()
            MiniGradient.Color = miniBossEnabled and TOGGLE_ON or TOGGLE_OFF
            MiniStroke.Transparency = miniBossEnabled and 0.6 or 0.3
            tween(MiniKnob, {Position = miniBossEnabled and UDim2.new(1, -25, 0.5, -11)
                or UDim2.new(0, 3, 0.5, -11)}, 0.18)
            if #miniSelectionOrder == 0 then
                MiniSelectButton.Text = "Select Mini Boss"
            elseif #miniSelectionOrder == 1 then
                local only = miniByName[miniSelectionOrder[1]]
                MiniSelectButton.Text = only.name .. "  [Lv. " .. only.level .. "+]"
            else
                MiniSelectButton.Text = tostring(#miniSelectionOrder) .. " Mini Bosses Selected"
            end
            for _, entry in ipairs(miniBossCatalog) do
                local on = miniSelected[entry.name] == true
                local row = miniRows[entry.name]
                row.Text = (on and "✓  " or "    ") .. "Lv. " .. entry.level .. "+  •  " .. entry.name
                row.TextColor3 = on and farmPalette.text or farmPalette.muted
            end
        end

        local function miniActive(token)
            return miniBossEnabled and miniBossToken == token and not destroyed
        end

        -- Match only the selected boss, never a different mini boss or a player.
        -- A boss may use its Model.Name or a BillboardGui nameplate. Normalize
        -- spacing/case but enforce word boundaries (Robot 15 != Robot 16).
        local function miniNormalize(value)
            local raw = tostring(value or ""):gsub("(%l)(%u)", "%1 %2")
            raw = raw:lower():gsub("<[^>]*>", " ")
            raw = raw:gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
            raw = raw:gsub("[^%w]+", " "):gsub("%s+", " ")
            return raw:match("^%s*(.-)%s*$") or ""
        end
        local function miniNameMatches(value, entry)
            local normalized = miniNormalize(value)
            if normalized=="" then return false end
            for _,name in ipairs({entry.name,table.unpack(entry.aliases or {})}) do
                local key=miniNormalize(name)
                if (" "..normalized.." "):find(" "..key.." ",1,true) then return true end
            end
            return false
        end
        local function miniModelMatches(model, entry)
            if miniNameMatches(model.Name, entry) then return true end
            local humanoid=getMobHumanoid(model)
            if humanoid and miniNameMatches(humanoid.DisplayName,entry) then return true end
            local cached = miniNameCache[model]
            local now = os.clock()
            if cached and cached.name == entry.name and cached.expires > now then return cached.found end
            local found = false
            for _, descendant in ipairs(model:GetDescendants()) do
                if descendant:IsA("TextLabel") and descendant:FindFirstAncestorWhichIsA("BillboardGui")
                    and miniNameMatches(descendant.Text, entry) then
                    found = true
                    break
                end
            end
            miniNameCache[model] = {name = entry.name, found = found, expires = now + 3}
            return found
        end
        local function findMiniAtCamp(entry)
            if typeof(entry.position)~="Vector3" then return nil end
            local winner, best = nil, entry.dynamic and math.huge or MINI_SEARCH_RADIUS * MINI_SEARCH_RADIUS
            for humanoid in pairs(World.humanoids) do
                if humanoid.Parent and humanoid.Health > 0 then
                    local model = humanoid.Parent
                    if model and model:IsA("Model") and model:IsDescendantOf(workspace)
                        and model ~= LocalPlayer.Character and not Players:GetPlayerFromCharacter(model)
                        and not model:FindFirstAncestorWhichIsA("WorldModel") and not model:FindFirstAncestorWhichIsA("Camera") then
                        local mobRoot = getMobRoot(model)
                        if mobRoot then
                            local delta = mobRoot.Position - entry.position
                            local distanceSq = delta:Dot(delta)
                            if distanceSq <= best and miniModelMatches(model, entry) and not farmQuestGiver(model)
                                and not model:FindFirstChildWhichIsA("ProximityPrompt",true)
                                and not model:FindFirstChildWhichIsA("ClickDetector",true) then
                                winner, best = model, distanceSq
                            end
                        end
                    end
                end
            end
            if winner and entry.dynamic then
                local part=getMobRoot(winner)
                if part then entry.position,entry.islandFallback=part.Position,false end
            end
            return winner
        end

        -- TP begins only when the Auto Mini Boss toggle is enabled. For jumps
        -- above 500 studs, use the shared gradual visibility transition.
        local function miniTeleport(entry, token, revision)
            local char, root = Motion.character()
            if not miniActive(token) or not char or not root then return false end
            if not Motion.allowed("Farm") or (Motion.owner and Motion.owner ~= "Farm") then return false end
            if entry.dynamic then findMiniAtCamp(entry) end
            if typeof(entry.position)~="Vector3" then return false end
            local arrival = entry.position + Vector3.new(0, 3, 0)
            if (root.Position - arrival).Magnitude <= 22 then return true end
            if SafeMode.Enabled then
                return Motion.walkTo("Farm", arrival, nil, function()
                    return miniActive(token) and revision == miniSelectionVersion and Motion.allowed("Farm")
                end, 18)
            end
            Motion.release("Farm")
            local longJump = TeleportLoading.isLong(root, arrival)
            local ticket = longJump and TeleportLoading.begin("miniBoss", "TRAVELING TO " .. entry.name:upper()) or nil
            if ticket then
                TeleportLoading.preload(ticket, arrival)
                task.wait(0.5)
            end
            if not miniActive(token) or revision ~= miniSelectionVersion or not Motion.allowed("Farm") then
                if ticket then TeleportLoading.finish(ticket) end
                return false
            end
            char, root = Motion.character()
            if not char or not root then
                if ticket then TeleportLoading.finish(ticket) end
                return false
            end
            local moved = Motion.pivotDirect(char, root, CFrame.new(arrival))
            if not miniActive(token) or revision ~= miniSelectionVersion then
                if ticket then TeleportLoading.finish(ticket) end
                return false
            end
            if ticket then TeleportLoading.fadeOut(ticket) end
            return moved == true
        end

        stopMiniBoss = function()
            miniBossEnabled = false
            miniBossToken = miniBossToken + 1
            if miniBossThread then pcall(task.cancel, miniBossThread); miniBossThread = nil end
            miniTarget = nil
            TeleportLoading.cancelOwner("miniBoss")
            Motion.release("Farm")
            if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
            QuestRuntime.AutoFarmEnabled = autoFarmEnabled or WorldBoss.Enabled
            renderMini()
        end

        local function startMiniBoss()
            if miniBossEnabled then return end
            if #miniSelectionOrder == 0 then
                warn("[Random Hub | Auto Mini Boss] Select at least one mini boss first.")
                return
            end
            if WorldBoss.Enabled and type(WorldBoss.Stop) == "function" then WorldBoss.Stop() end
            if autoFarmEnabled then disableAutoFarm() end
            miniBossEnabled = true
            QuestRuntime.AutoFarmEnabled = true
            miniBossToken = miniBossToken + 1
            local token = miniBossToken
            renderMini()
            miniBossThread = task.spawn(function()
                while miniActive(token) do
                    local revision = miniSelectionVersion
                    local snapshot = {}
                    for _, name in ipairs(miniSelectionOrder) do
                        if miniSelected[name] and miniByName[name] then
                            snapshot[#snapshot + 1] = miniByName[name]
                        end
                    end
                    if #snapshot == 0 then
                        task.wait(0.3)
                    else
                        for _, entry in ipairs(snapshot) do
                            if not miniActive(token) or revision ~= miniSelectionVersion then break end
                            -- Pause rather than stealing movement from a quest or another feature.
                            while miniActive(token) and revision == miniSelectionVersion
                                and not Motion.allowed("Farm") do
                                Motion.release("Farm")
                                task.wait(0.3)
                            end
                            if not miniActive(token) or revision ~= miniSelectionVersion then break end
                            local ok, err = pcall(function()
                                local reached = miniTeleport(entry, token, revision)
                                if not reached then task.wait(0.3); return end
                                local found
                                local searchStarted = os.clock()
                                -- Give the server a short chance to stream the boss near spawn.
                                repeat
                                    if not miniActive(token) or revision ~= miniSelectionVersion then return end
                                    found = findMiniAtCamp(entry)
                                    if found then break end
                                    task.wait(0.2)
                                until os.clock() - searchStarted >= 1.8
                                if not found then return end  -- not spawned: visit the next selection

                                miniTarget = found
                                local lastProgress = os.clock()
                                local lastHealth = math.huge
                                while miniActive(token) and revision == miniSelectionVersion do
                                    if not Motion.allowed("Farm") then
                                        Motion.release("Farm")
                                        task.wait(0.3)
                                    else
                                        local humanoid = getMobHumanoid(found)
                                        local part = getMobRoot(found)
                                        if not found.Parent or not found:IsDescendantOf(workspace)
                                            or not humanoid or humanoid.Health <= 0 or not part then break end
                                        if humanoid.Health < lastHealth then lastProgress = os.clock() end
                                        lastHealth = humanoid.Health
                                        if (part.Position - entry.position).Magnitude > 350 then break end
                                        if os.clock() - lastProgress > 45 then break end -- stuck, try next boss
                                        Motion.request("Farm", found, math.clamp(tonumber(farmDistance) or 1, 1, 10), "mob")
                                        task.wait(0.16)
                                    end
                                end
                                miniTarget = nil
                                Motion.release("Farm")
                                task.wait(0.25)
                            end)
                            if not ok then
                                if os.clock() - miniLastWarning > 7 then
                                    warn("[Random Hub | Auto Mini Boss] " .. tostring(err))
                                    miniLastWarning = os.clock()
                                end
                                miniTarget = nil
                                Motion.release("Farm")
                                task.wait(0.45)
                            end
                        end
                        -- Wait a little before checking the selected route again.
                        if miniActive(token) then task.wait(3.5) end
                    end
                end
                if miniBossThread == coroutine.running() then miniBossThread = nil end
            end)
        end

        for _, entry in ipairs(miniBossCatalog) do
            local row = miniRows[entry.name]
            connect(row.MouseButton1Click, function()
                if destroyed then return end
                if miniSelected[entry.name] then
                    miniSelected[entry.name] = nil
                    for i, name in ipairs(miniSelectionOrder) do
                        if name == entry.name then table.remove(miniSelectionOrder, i); break end
                    end
                else
                    miniSelected[entry.name] = true
                    miniSelectionOrder[#miniSelectionOrder + 1] = entry.name
                end
                miniSelectionVersion = miniSelectionVersion + 1
                renderMini() -- keep the list open for multi-selection
            end)
        end
        connect(MiniSelectButton.MouseButton1Click, function()
            if destroyed then return end
            if FarmTargetDropdown then FarmTargetDropdown.Visible = false end
            if BossDropdown then BossDropdown.Visible = false end
            MiniBossDropdown.Visible = not MiniBossDropdown.Visible
            MiniCard.Size = UDim2.new(1, 0, 0, MiniBossDropdown.Visible and 324 or 96)
        end)
        connect(MiniToggle.MouseButton1Click, function()
            if miniBossEnabled then stopMiniBoss() else startMiniBoss() end
        end)
        Stoppers.MiniBoss = function()
            stopMiniBoss()
            MiniBossDropdown.Visible = false
            MiniCard.Size = UDim2.new(1, 0, 0, 96)
        end
        renderMini()
    end

    -- AUTO WORLD BOSS (manual catalog, matching the Select Target / TP Island design).
    -- This catalog is deliberately NOT built from NPC scans. Only the *selected* boss
    -- is located in the world, within 250 studs of its manually defined spawn point.
    local BossToggleCard = createStyledCard(AutoFarmPage, "AutoWorldBossToggleCard", 52, 7)
    local BossToggleTitle = Instance.new("TextLabel")
    BossToggleTitle.Name = "AutoWorldBossTitle"
    BossToggleTitle.Size = UDim2.new(1, -100, 0, 26)
    BossToggleTitle.Position = UDim2.fromOffset(16, 11)
    BossToggleTitle.BackgroundTransparency = 1
    BossToggleTitle.Text = "Auto Summon Boss"
    BossToggleTitle.TextColor3 = Theme.Text
    BossToggleTitle.Font = Enum.Font.GothamBold
    BossToggleTitle.TextSize = 15
    BossToggleTitle.TextXAlignment = Enum.TextXAlignment.Left
    BossToggleTitle.Parent = BossToggleCard

    local BossTrack = Instance.new("TextButton")
    BossTrack.Name = "AutoWorldBossToggle"
    BossTrack.Size = UDim2.fromOffset(52, 28)
    BossTrack.Position = UDim2.new(1, -68, 0, 11)
    BossTrack.BackgroundColor3 = Color3.new(1, 1, 1)
    BossTrack.BorderSizePixel = 0
    BossTrack.Text = ""
    BossTrack.AutoButtonColor = false
    BossTrack.Parent = BossToggleCard
    addCorner(BossTrack, 14)
    local BossTrackStroke = addStroke(BossTrack, Theme.Stroke, 1, 0.3)
    local BossTrackGradient = Instance.new("UIGradient")
    BossTrackGradient.Color = TOGGLE_OFF
    BossTrackGradient.Parent = BossTrack
    local BossKnob = Instance.new("Frame")
    BossKnob.Name = "Knob"
    BossKnob.Size = UDim2.fromOffset(22, 22)
    BossKnob.Position = UDim2.new(0, 3, 0.5, -11)
    BossKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    BossKnob.BorderSizePixel = 0
    BossKnob.Parent = BossTrack
    addCorner(BossKnob, 11)

    local BossCard = createStyledCard(AutoFarmPage, "WorldBossSelectorCard", 96, 8)
    -- Match the Auto World Boss toggle's gray surface and gradient.
    BossCard.BackgroundColor3 = BossToggleCard.BackgroundColor3
    BossCard.ZIndex = 3
    local BossSelectTitle = Instance.new("TextLabel")
    BossSelectTitle.Name = "WorldBossSectionTitle"
    BossSelectTitle.Size = UDim2.new(1, -20, 0, 25)
    BossSelectTitle.Position = UDim2.fromOffset(10, 8)
    BossSelectTitle.BackgroundTransparency = 1
    BossSelectTitle.Text = "Select Summon Boss"
    BossSelectTitle.TextColor3 = farmPalette.text
    BossSelectTitle.Font = Enum.Font.GothamBold
    BossSelectTitle.TextSize = 18
    BossSelectTitle.TextXAlignment = Enum.TextXAlignment.Left
    BossSelectTitle.Parent = BossCard

    local BossSelectButton = Instance.new("TextButton")
    BossSelectButton.Name = "SelectWorldBoss"
    BossSelectButton.Size = UDim2.new(1, -16, 0, 36)
    BossSelectButton.Position = UDim2.fromOffset(8, 42)
    BossSelectButton.BackgroundColor3 = farmPalette.input
    BossSelectButton.BorderSizePixel = 0
    BossSelectButton.Text = "Select Summon Boss"
    BossSelectButton.Font = Enum.Font.Gotham
    BossSelectButton.TextSize = 13
    BossSelectButton.TextColor3 = farmPalette.text
    BossSelectButton.TextXAlignment = Enum.TextXAlignment.Left
    BossSelectButton.ZIndex = 6
    BossSelectButton.Parent = BossCard
    addCorner(BossSelectButton, 9)
    local BossPad = Instance.new("UIPadding")
    BossPad.PaddingLeft = UDim.new(0, 12)
    BossPad.PaddingRight = UDim.new(0, 12)
    BossPad.Parent = BossSelectButton

    BossDropdown = Instance.new("Frame")
    BossDropdown.Name = "WorldBossDropdown"
    BossDropdown.Size = UDim2.new(1, -16, 0, 89)
    BossDropdown.Position = UDim2.fromOffset(8, 80)
    BossDropdown.BackgroundColor3 = Theme.Card
    BossDropdown.BorderSizePixel = 0
    BossDropdown.ZIndex = 15
    BossDropdown.Visible = false
    BossDropdown.Parent = BossCard
    addCorner(BossDropdown, 9)
    addStroke(BossDropdown, Color3.fromRGB(66, 67, 79), 1, 0.1)

    -- Manual entries, sorted by recommended level. No scan is used to fill this list.
    local summonBossCatalog = {
        {name = "Dual Swordsman", level = 235},
        {name = "Cursed Prodigy", level = 245},
    }
    local bossRows = {}
    for index, entry in ipairs(summonBossCatalog) do
        local row = Instance.new("TextButton")
        row.Name = "WorldBoss_" .. entry.name:gsub("[^%w]", "")
        row.Size = UDim2.new(1, -12, 0, 34)
        row.Position = UDim2.fromOffset(6, 7 + (index - 1) * 40)
        row.BackgroundColor3 = farmPalette.input
        row.BorderSizePixel = 0
        row.Text = entry.name .. " [Lv. " .. entry.level .. "+]"
        row.TextColor3 = farmPalette.muted
        row.TextSize = 12
        row.Font = Enum.Font.Gotham
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.ZIndex = 16
        row.Parent = BossDropdown
        addCorner(row, 7)
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 12)
        padding.Parent = row
        bossRows[entry.name] = row
    end

    -- Extra scroll space below the World Boss selector so the dropdown remains
    -- fully visible and clickable even on small screens.
    local BossScrollSpace = Instance.new("Frame")
    BossScrollSpace.Name = "WorldBossScrollSpace"
    BossScrollSpace.Size = UDim2.new(1, 0, 0, 160)
    BossScrollSpace.BackgroundTransparency = 1
    BossScrollSpace.BorderSizePixel = 0
    BossScrollSpace.LayoutOrder = 9
    BossScrollSpace.Parent = AutoFarmPage

    -- Spawn coordinates for each summon boss are integrated into WorldBoss.Camp above.
    -- No separate Boss Spawn panel, input, saved override or extra buttons.

    local bossThread = nil
    local bossToken = 0
    local bossLastMissingWarning = -math.huge
    local function bossRender()
        BossTrackGradient.Color = WorldBoss.Enabled and TOGGLE_ON or TOGGLE_OFF
        BossTrackStroke.Transparency = WorldBoss.Enabled and 0.6 or 0.3
        tween(BossKnob, {
            Position = WorldBoss.Enabled and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11),
        }, 0.18)
        BossSelectButton.Text = WorldBoss.Selected or "Select Summon Boss"
        for _, entry in ipairs(summonBossCatalog) do
            local row = bossRows[entry.name]
            local selected = WorldBoss.Selected == entry.name
            row.Text = (selected and "✓  " or "") .. entry.name .. " [Lv. " .. entry.level .. "+]"
            row.TextColor3 = selected and farmPalette.text or farmPalette.muted
        end
    end

    local function worldBossCamp()
        local position = WorldBoss.Selected and WorldBoss.Camp[WorldBoss.Selected]
        return typeof(position) == "Vector3" and position or nil
    end

    local function bossNameMatches(value, selected)
        if not selected or not WorldBoss.Camp[selected] then return false end
        local name = string.lower(tostring(value or ""))
        -- Match only the manually chosen boss, including BillboardGui boss labels.
        name = name:gsub("%b[]", " "):gsub("%b()", " ")
        name = name:gsub("%f[%a]boss%f[%A]", " "):gsub("[%s_%-]+", " ")
        if name:find(string.lower(tostring(selected)), 1, true) then return true end
        local recipe = WorldBoss.Requirements[selected]
        for _, alias in ipairs(recipe and recipe.BossAliases or {}) do
            if (" " .. name .. " "):find(" " .. alias:lower() .. " ", 1, true) then return true end
        end
        return false
    end

    local bossNameCache = setmetatable({}, {__mode = "k"})
    local function bossModelMatches(model)
        local selected = WorldBoss.Selected
        if bossNameMatches(model.Name, selected) then return true end
        local cache = bossNameCache[model]
        if cache and cache.selected == selected and os.clock() < cache.untilTime then return cache.found end
        local found = false
        -- Some bosses expose the name in an attached BillboardGui rather than Model.Name.
        for _, obj in ipairs(model:GetDescendants()) do
            if obj:IsA("TextLabel") and obj:FindFirstAncestorWhichIsA("BillboardGui")
                and bossNameMatches(obj.Text, selected) then
                found = true
                break
            end
        end
        bossNameCache[model] = {selected=selected, found=found, untilTime=os.clock()+4}
        return found
    end

    local function bossNearCamp(camp)
        local winner, distanceSq = nil, WorldBoss.SearchRadius * WorldBoss.SearchRadius
        for humanoid in pairs(World.humanoids) do
            if humanoid.Parent and humanoid.Health > 0 then
                local model = humanoid.Parent
                if model and model:IsA("Model") and model:IsDescendantOf(workspace)
                    and model ~= LocalPlayer.Character and not Players:GetPlayerFromCharacter(model)
                    and bossModelMatches(model) then
                    local mobRoot = getMobRoot(model)
                    if mobRoot then
                        local delta = mobRoot.Position - camp
                        local dist = delta:Dot(delta)
                        if dist <= distanceSq then winner, distanceSq = model, dist end
                    end
                end
            end
        end
        return winner
    end

    local function bossTeleportCamp(camp, token)
        local character, root = Motion.character()
        if not WorldBoss.Enabled or (token and bossToken ~= token) or not character or not root then return false end
        -- Never interfere with a quest or another movement owner.
        if not Motion.allowed("Farm") or (Motion.owner and Motion.owner ~= "Farm") then return false end
        local arrival = camp + Vector3.new(0, 3, 0)
        if SafeMode.Enabled then
            local sessionToken, selected = token or bossToken, WorldBoss.Selected
            return Motion.walkTo("Farm", arrival, nil, function()
                return not destroyed and WorldBoss.Enabled and bossToken == sessionToken
                    and WorldBoss.Selected == selected and Motion.allowed("Farm")
            end, 18)
        end
        Motion.release("Farm")
        local longJump = TeleportLoading.isLong(root, arrival)
        local ticket = longJump and TeleportLoading.begin("boss", "TRAVELING TO WORLD BOSS") or nil
        if ticket then
            TeleportLoading.preload(ticket, arrival)
            task.wait(0.5)
        end
        if destroyed or not WorldBoss.Enabled or (token and bossToken ~= token) or not Motion.allowed("Farm") then
            TeleportLoading.finish(ticket)
            return false
        end
        character, root = Motion.character()
        if not character or not root then
            TeleportLoading.finish(ticket)
            return false
        end
        local moved = Motion.pivotDirect(character, root, CFrame.new(arrival))
        if destroyed or not WorldBoss.Enabled or (token and bossToken ~= token) then
            TeleportLoading.finish(ticket)
            return false
        end
        if ticket then TeleportLoading.fadeOut(ticket) end
        return moved == true
    end

    -- The summon NPC depends on the selected boss: Seraphina or Noko.
    -- Find NPCs by their actual in-game name/label, never a guessed remote.
    local lastSummonerWarning = -math.huge
    local bossOwnsInteraction = false
    local bossHubHidden = false
    local bossHubRestoreEnabled = nil
    local function bossReleaseInteraction()
        if bossOwnsInteraction then
            QuestRuntime.Interacting = false
            bossOwnsInteraction = false
        end
        if bossHubHidden then
            bossHubHidden = false
            if not destroyed then ScreenGui.Enabled = bossHubRestoreEnabled and uiOpen end
            bossHubRestoreEnabled = nil
        end
    end
    local function warnSummoner(message)
        if os.clock() - lastSummonerWarning >= 10 then
            warn("[Random Hub | Auto Summon Boss] " .. tostring(message))
            lastSummonerWarning = os.clock()
        end
    end

    local function summonerName(value, npcName)
        if type(npcName) ~= "string" or npcName == "" then return false end
        local raw = string.lower(tostring(value or ""))
        raw = raw:gsub("<[^>]*>", ""):gsub("[%s_%-]+", " ")
        return raw:find(string.lower(tostring(npcName)), 1, true) ~= nil
    end

    local function summonerNPC(npcName)
        local function suitable(model)
            return model and model:IsA("Model") and model.Parent
                and model:IsDescendantOf(workspace) and model ~= LocalPlayer.Character
                and not Players:GetPlayerFromCharacter(model)
                and (getMobRoot(model) or model:FindFirstChildWhichIsA("BasePart", true))
        end
        for humanoid in pairs(World.humanoids) do
            local model = humanoid.Parent
            if suitable(model) and (summonerName(model.Name, npcName) or summonerName(humanoid.DisplayName, npcName)) then
                return model
            end
        end
        for node in pairs(World.texts) do
            if node.Parent and node:IsA("TextLabel") and summonerName(node.Text, npcName)
                and node:FindFirstAncestorWhichIsA("BillboardGui") then
                local model = AcceptQuest.npcFor(node)
                if suitable(model) then return model end
            end
        end
        -- Fallback only when needed, never an every-frame full-map scan.
        local named = workspace:FindFirstChild(npcName, true)
        if suitable(named) then return named end
        if named then
            local model = named:FindFirstAncestorWhichIsA("Model")
            if suitable(model) then return model end
        end
        return nil
    end

    local function bossSessionActive(token)
        return not destroyed and WorldBoss.Enabled and bossToken == token
            and Motion.allowed("Farm") and Motion.character() ~= nil
    end

    local function bossTeleportNPC(npc, token)
        if not bossSessionActive(token) then return false end
        local part = npc and getMobRoot(npc)
        local character, root = Motion.character()
        if not part or not character or not root then return false end
        local face = part.CFrame.LookVector
        local destination = part.Position + face * 4 + Vector3.new(0, 2, 0)
        if SafeMode.Enabled then
            return Motion.walkTo("Farm", destination, npc, function()
                return bossSessionActive(token) and part.Parent ~= nil
            end, 2)
        end
        local longJump = TeleportLoading.isLong(root, destination)
        local ticket = longJump and TeleportLoading.begin("boss") or nil
        if ticket then
            TeleportLoading.preload(ticket, destination)
            task.wait(0.5)
        end
        if not bossSessionActive(token) or not part.Parent then
            if ticket then TeleportLoading.finish(ticket) end
            return false
        end
        character, root = Motion.character()
        if not character or not root then
            if ticket then TeleportLoading.finish(ticket) end
            return false
        end
        Motion.release("Farm")
        local moved = Motion.pivotDirect(character, root,
            CFrame.lookAt(destination, part.Position + Vector3.new(0, 1, 0)))
        if ticket then TeleportLoading.fadeOut(ticket) end
        return moved == true
    end

    local function summonerClickNPC(npc, token, forceHuman)
        if not bossSessionActive(token) or not npc or not npc.Parent then return false end
        local _, root = Motion.character()
        local part = npc:FindFirstChild("Head", true) or getMobRoot(npc)
        if not root or not part or (part.Position - root.Position).Magnitude > 16 then return false end
        -- Use standard Roblox interactions first; don't guess server remotes.
        for _, node in ipairs(forceHuman and {} or npc:GetDescendants()) do
            if node:IsA("ClickDetector") then
                if type(fireclickdetector) == "function" and pcall(fireclickdetector, node) then return true end
                if World.emit(node.MouseClick, LocalPlayer) then return true end
            elseif node:IsA("ProximityPrompt") and node.Enabled then
                local action = string.lower(tostring(node.ActionText or ""))
                if action == "" or action:find("talk", 1, true) or action:find("interact", 1, true)
                    or action:find("speak", 1, true) or action:find("summon", 1, true) then
                    if type(fireproximityprompt) == "function" and pcall(fireproximityprompt, node) then return true end
                    if World.emit(node.Triggered, LocalPlayer) then return true end
                    local okay = pcall(function()
                        node:InputHoldBegin()
                        task.wait(math.min(node.HoldDuration + 0.06, 2.5))
                        node:InputHoldEnd()
                    end)
                    if okay then return true end
                end
            end
        end
        -- The screenshot shows INTERACT [CLICK]; fall back to a real client click
        -- on the NPC's visible head when no prompt/detector is exposed.
        local camera = workspace.CurrentCamera
        if not camera or not part:IsA("BasePart") then return false end
        local cp = camera.CFrame.Position
        if (part.Position - cp).Magnitude > 0.1 then
            pcall(function() camera.CFrame = CFrame.lookAt(cp, part.Position) end)
        end
        task.wait(0.1)
        if not bossSessionActive(token) then return false end
        local pixel, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or pixel.Z <= 0 then return false end
        local x, y = math.floor(pixel.X), math.floor(pixel.Y)
        if x < 1 or y < 1 or x >= camera.ViewportSize.X or y >= camera.ViewportSize.Y then return false end
        local oldEnabled = ScreenGui.Enabled
        bossHubRestoreEnabled, bossHubHidden = oldEnabled, true
        ScreenGui.Enabled = false
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        local clicked = false
        if VirtualInputManager then
            clicked = pcall(function()
                VirtualInputManager:SendMouseMoveEvent(x, y, game)
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                task.wait(0.08)
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
            pcall(function() VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
        end
        if not clicked and VirtualUser then
            clicked = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:Button1Down(Vector2.new(x, y), camera.CFrame)
                task.wait(0.08)
                VirtualUser:Button1Up(Vector2.new(x, y), camera.CFrame)
            end)
            pcall(function() VirtualUser:Button1Up(Vector2.new(x, y), camera.CFrame) end)
        end
        if not destroyed then ScreenGui.Enabled = oldEnabled and uiOpen end
        bossHubHidden, bossHubRestoreEnabled = false, nil
        return clicked
    end

    local function summonButtonText(button)
        local text = button:IsA("TextButton") and tostring(button.Text or "") or ""
        if text == "" then
            for _, child in ipairs(button:GetDescendants()) do
                if child:IsA("TextLabel") and child.Text ~= "" then
                    text = text .. " " .. child.Text
                end
            end
        end
        return string.lower(AcceptQuest.markerText(text)):gsub("[%[%]]", "")
    end

    local function summonerOption(before, selected)
        local winner, best = nil, 0
        for node in pairs(World.gui) do
            if node:IsA("GuiButton") and node.Parent and node.Active ~= false
                and AcceptQuest.visible(node) and not node:IsDescendantOf(ScreenGui) then
                local label = summonButtonText(node)
                local newButton = not before[node]
                local score = 0
                if selected and label:find(string.lower(tostring(selected)), 1, true) then score = 110
                elseif label:find("summon", 1, true) or label:find("spawn", 1, true) then score = 100
                elseif label:find("challenge", 1, true) or label:find("fight", 1, true) then score = 75
                elseif newButton and (label:find("sure", 1, true) or label:find("yes", 1, true)
                    or label:find("confirm", 1, true) or label:find("accept", 1, true)) then score = 45 end
                -- Do not click shop, purchase, key or unrelated account buttons.
                if label:find("buy", 1, true) or label:find("shop", 1, true)
                    or label:find("robux", 1, true) or label:find("cancel", 1, true)
                    or label:find("close", 1, true) then score = 0 end
                -- A generic confirmation must belong to the newly opened dialog.
                if score > 0 and (newButton or score >= 100) and score > best then
                    best, winner = score, node
                end
            end
        end
        return winner
    end

    local SummonMaterial = {
        blocked = setmetatable({}, {__mode = "k"}),
        names = setmetatable({}, {__mode = "k"}),
        toolItems = {},
        dropCooldown = setmetatable({}, {__mode = "k"}),
    }
    function SummonMaterial.reset()
        SummonMaterial.inventoryAt, SummonMaterial.inventoryItem, SummonMaterial.inventoryCount = 0, nil, 0
        SummonMaterial.arrived, SummonMaterial.travelAt = false, -math.huge
        SummonMaterial.searchAt, SummonMaterial.dropUntil, SummonMaterial.pendingUntil = 0, 0, 0
        SummonMaterial.lastHealth, SummonMaterial.progressAt = nil, 0
        SummonMaterial.pickup, SummonMaterial.pickupUntil, SummonMaterial.pickupAt = nil, 0, 0
        WorldBoss.MaterialTarget, WorldBoss.Phase = nil, nil
    end
    function SummonMaterial.key(value)
        local text = tostring(value or ""):lower():gsub("<[^>]*>", " ")
        text = text:gsub("%b[]", " "):gsub("%b()", " ")
        text = text:gsub("%s*[x×]%s*%d+%s*$", ""):gsub("^%s*%d+%s*[x×]%s*", "")
        return text:gsub("[^%w]", "")
    end
    function SummonMaterial.number(value)
        if value == true then return 1 end
        if value == false then return 0 end
        local count = tonumber(value)
        if not count and type(value) == "string" then
            local raw = value:lower():gsub(",", "")
            count = tonumber(raw:match("^%s*[x×]%s*(%d+)%s*$") or raw:match("^%s*(%d+)%s*[x×]%s*$")
                or raw:match("owned%s*:?%s*(%d+)") or raw:match("amount%s*:?%s*(%d+)")
                or raw:match("quantity%s*:?%s*(%d+)") or raw:match("count%s*:?%s*(%d+)"))
        end
        return count and math.max(0, count) or nil
    end
    function SummonMaterial.quantity(object)
        local fields = {amount=true,quantity=true,count=true,stack=true,stacks=true,owned=true}
        for field, value in pairs(object:GetAttributes()) do
            if fields[string.lower(field)] then
                local count = SummonMaterial.number(value)
                if count ~= nil then return count end
            end
        end
        for _, child in ipairs(object:GetChildren()) do
            local field = string.lower(child.Name):gsub("[^%a]", "")
            if fields[field] then
                local count
                if child:IsA("ValueBase") then count = SummonMaterial.number(child.Value)
                elseif child:IsA("TextLabel") or child:IsA("TextButton") then count = SummonMaterial.number(child.Text) end
                if count ~= nil then return count end
            elseif child:IsA("TextLabel") then
                local count = SummonMaterial.number(child.Text)
                if count ~= nil and tostring(child.Text):match("[x×]") then return count end
            end
        end
        return nil
    end
    function SummonMaterial.inInventory(object)
        local cursor = object and object.Parent
        local inventory = false
        while cursor and cursor ~= LocalPlayer do
            if cursor == ScreenGui or cursor:IsA("Tool") then return false end
            local name = string.lower(cursor.Name):gsub("[^%a]", "")
            if name:find("shop", 1, true) or name:find("stock", 1, true)
                or name:find("dialog", 1, true) or name:find("catalog", 1, true) then return false end
            if name:find("inventory", 1, true) or name:find("backpack", 1, true)
                or name == "materials" or name == "items" or name == "storage" or name == "bag" then inventory = true end
            cursor = cursor.Parent
        end
        return inventory
    end
    function SummonMaterial.count(recipe, force)
        local now = os.clock()
        if not force and SummonMaterial.inventoryItem == recipe.Item and now < SummonMaterial.inventoryAt then
            return SummonMaterial.inventoryCount
        end
        local wanted, toolCount, dataCount, guiCount, dataSeen = SummonMaterial.key(recipe.Item), 0, 0, 0, false
        local function toolMatches(tool)
            if SummonMaterial.key(tool.Name) == wanted or SummonMaterial.key(tool.ToolTip) == wanted then return true end
            for field, value in pairs(tool:GetAttributes()) do
                local key = string.lower(field):gsub("[^%a]", "")
                if (key == "itemname" or key == "name" or key == "itemid")
                    and SummonMaterial.key(value) == wanted then return true end
            end
            return false
        end
        for _, container in pairs({LocalPlayer:FindFirstChildOfClass("Backpack"), LocalPlayer.Character}) do
            if container and container.Parent then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and toolMatches(tool) then
                        SummonMaterial.toolItems[wanted] = true
                        toolCount = toolCount + (SummonMaterial.quantity(tool) or 1)
                    end
                end
            end
        end
        for field, value in pairs(LocalPlayer:GetAttributes()) do
            if SummonMaterial.key(field) == wanted then
                local count = SummonMaterial.number(value)
                if count ~= nil then dataSeen, dataCount = true, math.max(dataCount, count) end
            end
        end
        for object in pairs(World.stats) do
            if object.Parent and object:IsDescendantOf(LocalPlayer) and not object:FindFirstAncestorWhichIsA("PlayerGui") then
                if SummonMaterial.key(object.Name) == wanted then
                    local count = object:IsA("ValueBase") and SummonMaterial.number(object.Value) or SummonMaterial.quantity(object)
                    if count ~= nil then dataSeen, dataCount = true, math.max(dataCount, count) end
                elseif object:IsA("StringValue") and SummonMaterial.key(object.Value) == wanted
                    and SummonMaterial.inInventory(object) then
                    local count = SummonMaterial.quantity(object.Parent)
                    if count ~= nil then dataSeen, dataCount = true, math.max(dataCount, count) end
                end
            end
        end
        for object in pairs(World.gui) do
            if object.Parent and not object:IsDescendantOf(ScreenGui)
                and (object:IsA("TextLabel") or object:IsA("TextButton"))
                and SummonMaterial.key(object.Text) == wanted and SummonMaterial.inInventory(object) then
                local row = object.Parent
                for _ = 1, 3 do
                    if not row or row:IsA("ScreenGui") or row:IsA("PlayerGui") then break end
                    local rowName = SummonMaterial.key(row.Name)
                    if rowName:find("inventory", 1, true) or rowName == "items" or rowName == "materials"
                        or rowName == "storage" or rowName == "bag" then break end
                    local count = SummonMaterial.quantity(row)
                    if count ~= nil then guiCount = math.max(guiCount, count); break end
                    row = row.Parent
                end
            end
        end
        local count = math.max(toolCount, dataCount)
        if count == 0 and not dataSeen and not SummonMaterial.toolItems[wanted] then count = guiCount end
        SummonMaterial.inventoryItem, SummonMaterial.inventoryCount, SummonMaterial.inventoryAt = recipe.Item, count, now + 0.5
        return count
    end
    function SummonMaterial.matches(value, recipe)
        local text = tostring(value or ""):gsub("(%l)(%u)", "%1 %2"):lower():gsub("<[^>]*>", " ")
        text = text:gsub("%b[]", " "):gsub("%b()", " ")
        text = text:gsub("lv%.?%s*%d+", " "):gsub("level%s*%d+", " "):gsub("%f[%a]boss%f[%A]", " ")
        text = text:gsub("[^%a]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        for _, alias in ipairs(recipe.SourceNames) do
            if text == alias:lower() then return true end
        end
        return false
    end
    function SummonMaterial.sourceMatches(model, humanoid, recipe)
        local cached = SummonMaterial.names[model]
        if cached and cached.recipe == recipe and cached.name == model.Name and cached.expires > os.clock() then return cached.valid end
        local found = SummonMaterial.matches(model.Name, recipe) or SummonMaterial.matches(humanoid.DisplayName, recipe)
        local rejected = false
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then rejected = true; break end
            if object:IsA("TextLabel") and object:FindFirstAncestorWhichIsA("BillboardGui")
                and SummonMaterial.matches(object.Text, recipe) then found = true end
        end
        found = found and not rejected
        SummonMaterial.names[model] = {recipe=recipe,name=model.Name,valid=found,expires=os.clock()+3}
        return found
    end
    function SummonMaterial.validTarget(model, recipe)
        if not model or not model.Parent or not model:IsDescendantOf(workspace)
            or model == LocalPlayer.Character or Players:GetPlayerFromCharacter(model) then return nil end
        local humanoid, root = getMobHumanoid(model), getMobRoot(model)
        if not humanoid or humanoid.Health <= 0 or not root
            or (root.Position - recipe.Position).Magnitude > 250 then return nil end
        if not SummonMaterial.sourceMatches(model, humanoid, recipe) then return nil end
        return humanoid, root
    end
    function SummonMaterial.findSource(recipe)
        local nearest, best = nil, math.huge
        for humanoid in pairs(World.humanoids) do
            local model = humanoid.Parent
            if model and model:IsA("Model") and os.clock() >= (SummonMaterial.blocked[model] or 0) then
                local valid, root = SummonMaterial.validTarget(model, recipe)
                if valid then
                    local delta = root.Position - recipe.Position
                    local distance = delta:Dot(delta)
                    if distance < best then nearest, best = model, distance end
                end
            end
        end
        return nearest
    end
    function SummonMaterial.attack(model, root)
        if not Motion.request("Farm", model, math.clamp(tonumber(farmDistance) or 1, 1, 10), "mob") then return end
    end
    function SummonMaterial.findDrop(recipe, root)
        local wanted, nearest, best = SummonMaterial.key(recipe.Item), nil, math.huge
        for object, key in pairs(WorldBoss.Drops) do
            if key == wanted and object.Parent and object:IsDescendantOf(workspace) and not World.held(object)
                and os.clock() >= (SummonMaterial.dropCooldown[object] or 0) then
                local part = World.root(object)
                if part then
                    local distance = (part.Position - root.Position).Magnitude
                    if distance < best then nearest, best = object, distance end
                end
            end
        end
        return nearest
    end
    function SummonMaterial.pickupStep(token, object, root)
        local now = os.clock()
        if not object.Parent or not object:IsDescendantOf(workspace) or World.held(object) then
            SummonMaterial.pickup, SummonMaterial.inventoryAt, SummonMaterial.dropUntil = nil, 0, now + 0.8
            Motion.release("Farm")
            return
        end
        if now >= SummonMaterial.pickupUntil then
            SummonMaterial.dropCooldown[object] = now + 20
            SummonMaterial.pickup = nil
            Motion.release("Farm")
            return
        end
        local part = World.root(object)
        if not part then SummonMaterial.pickup = nil; Motion.release("Farm"); return end
        if not Motion.request("Farm", object, 0, "item") then return end
        if (part.Position - root.Position).Magnitude > 5 or now < SummonMaterial.pickupAt then return end
        SummonMaterial.pickupAt = now + 0.8
        for _, node in ipairs(object:GetDescendants()) do
            if not bossSessionActive(token) then return end
            if node:IsA("ProximityPrompt") and node.Enabled then
                if type(fireproximityprompt) == "function" then pcall(fireproximityprompt, node)
                else World.emit(node.Triggered, LocalPlayer) end
            elseif node:IsA("ClickDetector") then
                if type(fireclickdetector) == "function" then pcall(fireclickdetector, node)
                else World.emit(node.MouseClick, LocalPlayer) end
            end
        end
        if bossSessionActive(token) and type(firetouchinterest) == "function" and part.Parent then
            pcall(function() firetouchinterest(root, part, 0); firetouchinterest(root, part, 1) end)
        end
        SummonMaterial.inventoryAt = 0
    end
    function SummonMaterial.step(token, recipe, root)
        local now = os.clock()
        if not SummonMaterial.pickup then
            local drop = SummonMaterial.findDrop(recipe, root)
            if drop then
                local part = World.root(drop)
                local distance = part and (root.Position - part.Position).Magnitude or 0
                local timeout = SafeMode.Enabled and math.clamp(distance / math.max(1, SafeMode.walkSpeed()) + 12, 15, 180) or 15
                SummonMaterial.pickup, SummonMaterial.pickupUntil = drop, now + timeout
                SummonMaterial.pickupAt = 0
                WorldBoss.MaterialTarget = nil
                if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
                Motion.release("Farm")
            end
        end
        if SummonMaterial.pickup then SummonMaterial.pickupStep(token, SummonMaterial.pickup, root); return end
        if not SummonMaterial.arrived then
            WorldBoss.MaterialTarget = nil
            Motion.release("Farm")
            if (root.Position - recipe.Position).Magnitude <= 30 then
                SummonMaterial.arrived, SummonMaterial.searchAt = true, 0
            elseif now - SummonMaterial.travelAt >= 2.5 then
                SummonMaterial.travelAt = now
                if bossTeleportCamp(recipe.Position, token) then SummonMaterial.arrived = true end
            end
            return
        end
        local target = WorldBoss.MaterialTarget
        local humanoid = SummonMaterial.validTarget(target, recipe)
        if target and not humanoid then
            WorldBoss.MaterialTarget = nil
            SummonMaterial.dropUntil, SummonMaterial.searchAt = now + 2.5, now + 2.5
            SummonMaterial.inventoryAt = 0
            SummonMaterial.lastHealth = nil
            Motion.release("Farm")
            return
        end
        if now < SummonMaterial.dropUntil then return end
        if not target and now >= SummonMaterial.searchAt then
            SummonMaterial.searchAt = now + 0.8
            target = SummonMaterial.findSource(recipe)
            WorldBoss.MaterialTarget = target
            humanoid = SummonMaterial.validTarget(target, recipe)
            SummonMaterial.lastHealth, SummonMaterial.progressAt = humanoid and humanoid.Health or nil, now
        end
        if humanoid and target then
            if not SummonMaterial.lastHealth or humanoid.Health < SummonMaterial.lastHealth then SummonMaterial.progressAt = now end
            SummonMaterial.lastHealth = humanoid.Health
            if now - SummonMaterial.progressAt > 45 then
                SummonMaterial.blocked[target] = now + 15
                WorldBoss.MaterialTarget = nil
                SummonMaterial.arrived = false
                Motion.release("Farm")
                return
            end
            SummonMaterial.attack(target, root)
        else
            Motion.release("Farm")
            if (root.Position - recipe.Position).Magnitude > 40 then SummonMaterial.arrived = false end
        end
    end

    local function summonViaNPC(token, camp)
        if not bossSessionActive(token) or bossNearCamp(camp) then return false end
        local selected = WorldBoss.Selected
        local npcName = selected and WorldBoss.Summoners[selected]
        local recipe = selected and WorldBoss.Requirements[selected]
        if not npcName or not recipe or SummonMaterial.count(recipe, true) < 1 then return false end
        local beforeCount = SummonMaterial.count(recipe)
        local npc = summonerNPC(npcName)
        if not npc then
            bossTeleportCamp(camp, token)
            task.wait(0.8)
            if not bossSessionActive(token) then return false end
            npc = summonerNPC(npcName)
        end
        if not npc then
            warnSummoner(npcName .. " not found in loaded workspace. Streaming may hide the NPC until nearby.")
            return false
        end
        if not bossTeleportNPC(npc, token) then return false end
        task.wait(0.75)
        if not bossSessionActive(token) or SummonMaterial.count(recipe, true) < 1 then return false end
        if bossNearCamp(camp) then return true end
        local before = {}
        for gui in pairs(World.gui) do
            if gui.Parent and gui:IsA("GuiButton") and AcceptQuest.visible(gui) then before[gui] = true end
        end
        if QuestRuntime.Interacting or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy then return false end
        QuestRuntime.Interacting = true
        bossOwnsInteraction = true
        local opened = summonerClickNPC(npc, token)
        local completed = false
        if opened then
            local deadline = os.clock() + 9
            local used = setmetatable({}, {__mode = "k"})
            local humanFallbackAt = os.clock() + 2.2
            local humanFallbackTried = false
            while bossSessionActive(token) and os.clock() < deadline do
                if bossNearCamp(camp) then completed = true; break end
                local option = summonerOption(before, selected)
                if option and not used[option] then
                    used[option] = true
                    if AcceptQuest.activateButton(option) then
                        -- Multi-stage dialogs may replace the previous choices.
                        task.wait(0.7)
                    else
                        task.wait(0.35)
                    end
                else
                    if not humanFallbackTried and os.clock() >= humanFallbackAt then
                        humanFallbackTried = true
                        summonerClickNPC(npc, token, true)
                    end
                    task.wait(0.3)
                end
            end
        else
            warnSummoner("Could not open " .. npcName .. " dialogue. Check the NPC interaction UI.")
        end
        bossReleaseInteraction()
        if bossSessionActive(token) and SummonMaterial.count(recipe, true) < beforeCount then
            SummonMaterial.pendingUntil = os.clock() + 12
            SummonMaterial.arrived = false
        end
        if bossSessionActive(token) then
            -- Search again at the selected boss coordinates, away from the summon NPC.
            bossTeleportCamp(camp, token)
            task.wait(1.0)
            completed = completed or bossNearCamp(camp) ~= nil
        end
        if not completed and opened and os.clock() >= SummonMaterial.pendingUntil then
            warnSummoner(npcName .. " was contacted, but " .. selected .. " was not confirmed. Dialogue options may differ.")
        end
        return completed
    end

    local function stopWorldBoss()
        WorldBoss.Enabled = false
        bossReleaseInteraction()
        TeleportLoading.cancelOwner("boss")
        WorldBoss.Target = nil
        SummonMaterial.reset()
        bossToken = bossToken + 1
        QuestRuntime.AutoFarmEnabled = autoFarmEnabled
        local previous = bossThread
        bossThread = nil
        if previous then pcall(task.cancel, previous) end
        Motion.release("Farm")
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        bossRender()
    end
    WorldBoss.Stop = stopWorldBoss

    local function startWorldBoss()
        if stopMiniBoss then stopMiniBoss() end
        if WorldBoss.Enabled then return end
        if not WorldBoss.Selected then
            warn("[Random Hub | Auto Summon Boss] Select a summon boss first.")
            return
        end
        if not worldBossCamp() or not WorldBoss.Requirements[WorldBoss.Selected] then return end
        if autoFarmEnabled then disableAutoFarm() end
        WorldBoss.Enabled, WorldBoss.Target = true, nil
        QuestRuntime.AutoFarmEnabled = true
        bossToken = bossToken + 1
        local token = bossToken
        SummonMaterial.reset()
        bossRender()
        local lastCampTeleport, lastSummonAttempt = -math.huge, -math.huge
        local nextSearchAt, bossMissingSince = 0, nil
        bossThread = task.spawn(function()
            task.wait()
            while WorldBoss.Enabled and bossToken == token and not destroyed do
                local ok, err = pcall(function()
                    local camp = worldBossCamp()
                    local recipe = WorldBoss.Requirements[WorldBoss.Selected]
                    if not camp or not recipe then task.wait(0.5); return end
                    if not Motion.allowed("Farm") or QuestRuntime.Interacting or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy then
                        Motion.release("Farm")
                        task.wait(0.35)
                        return
                    end
                    local character, root = Motion.character()
                    if not character or not root then
                        WorldBoss.MaterialTarget = nil
                        SummonMaterial.arrived, SummonMaterial.inventoryAt = false, 0
                        Motion.release("Farm")
                        task.wait(0.4)
                        return
                    end
                    local boss = WorldBoss.Target
                    if boss then
                        local humanoid = getMobHumanoid(boss)
                        if not boss.Parent or not boss:IsDescendantOf(workspace) or not humanoid or humanoid.Health <= 0 then
                            WorldBoss.Target = nil
                            bossMissingSince = nil
                            SummonMaterial.reset()
                            Motion.release("Farm")
                            bossTeleportCamp(camp, token)
                            lastCampTeleport, nextSearchAt = os.clock(), os.clock() + 1.5
                            task.wait(0.5)
                            return
                        end
                        if not getMobRoot(boss) then WorldBoss.Target = nil; Motion.release("Farm"); return end
                        WorldBoss.Phase = "BOSS"
                        SummonMaterial.attack(boss, root)
                        task.wait(0.16)
                        return
                    end
                    if os.clock() >= nextSearchAt then
                        nextSearchAt = os.clock() + 0.5
                        local found = bossNearCamp(camp)
                        if found then
                            WorldBoss.Target, WorldBoss.MaterialTarget, WorldBoss.Phase = found, nil, "BOSS"
                            bossMissingSince = nil
                            Motion.release("Farm")
                            task.wait(0.05)
                            return
                        end
                    end
                    if os.clock() < SummonMaterial.pendingUntil then
                        WorldBoss.Phase = "WAIT_SPAWN"
                        if (root.Position - camp).Magnitude > 25 and os.clock() - lastCampTeleport >= 2.5 then
                            if bossTeleportCamp(camp, token) then lastCampTeleport = os.clock() end
                        end
                        task.wait(0.4)
                        return
                    end
                    if SummonMaterial.count(recipe) < 1 then
                        WorldBoss.Phase = "MATERIAL"
                        bossMissingSince = nil
                        SummonMaterial.step(token, recipe, root)
                        task.wait(WorldBoss.MaterialTarget and 0.16 or 0.4)
                        return
                    end
                    if WorldBoss.MaterialTarget or SummonMaterial.pickup then
                        WorldBoss.MaterialTarget = nil
                        SummonMaterial.pickup = nil
                        Motion.release("Farm")
                        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
                    end
                    WorldBoss.Phase = "NPC"
                    bossMissingSince = bossMissingSince or os.clock()
                    if os.clock() - bossMissingSince >= 0.5 and os.clock() - lastSummonAttempt >= 18 then
                        lastSummonAttempt = os.clock()
                        if summonViaNPC(token, camp) then WorldBoss.Target = bossNearCamp(camp) end
                        lastCampTeleport, bossMissingSince = os.clock(), nil
                        nextSearchAt = 0
                    end
                    task.wait(0.35)
                end)
                if not ok then
                    if os.clock() - bossLastMissingWarning > 8 then
                        warn("[Random Hub | Auto Summon Boss] " .. tostring(err))
                        bossLastMissingWarning = os.clock()
                    end
                    bossReleaseInteraction()
                    Motion.release("Farm")
                    task.wait(0.5)
                end
            end
            if bossThread == coroutine.running() then bossThread = nil end
        end)
    end

    connect(BossSelectButton.MouseButton1Click, function()
        if destroyed then return end
        if FarmTargetDropdown then FarmTargetDropdown.Visible = false end
        if closeMiniBossDropdown then closeMiniBossDropdown() end
        BossDropdown.Visible = not BossDropdown.Visible
    end)
    for _, entry in ipairs(summonBossCatalog) do
        local name = entry.name
        connect(bossRows[name].MouseButton1Click, function()
            if destroyed then return end
            -- Selecting a boss never teleports; toggling Auto Summon Boss starts travel.
            -- Switching the choice while running cancels the old boss session safely.
            if WorldBoss.Enabled then stopWorldBoss() end
            WorldBoss.Selected = name
            WorldBoss.Target = nil
            BossDropdown.Visible = false
            bossRender()
        end)
    end
    connect(BossTrack.MouseButton1Click, function()
        if WorldBoss.Enabled then stopWorldBoss() else startWorldBoss() end
    end)
    Stoppers.WorldBoss = stopWorldBoss
    WorldBoss.Start = startWorldBoss
    WorldBoss.Refresh = bossRender
    WorldBoss.Materials = SummonMaterial
    WorldBoss.FindNPC = summonerNPC
    bossRender()

    local selectorWorker = task.spawn(function()
        local lastWorldRevision = -1
        local nextRefreshAllowed = 0
        local nextPeriodicRefresh = 0
        while not destroyed do
            if AutoFarmPage.Visible then
                local now = os.clock()
                local revision = World.revision
                local needsRefresh = not farmMobListInitialized
                    or revision ~= lastWorldRevision
                    or now >= nextPeriodicRefresh
                if needsRefresh and now >= nextRefreshAllowed then
                    local ok = pcall(function() refreshFarmMobTypes(false) end)
                    if ok then
                        lastWorldRevision = World.revision
                        nextRefreshAllowed = now + 0.8
                        nextPeriodicRefresh = now + 3
                    else
                        nextRefreshAllowed = now + 1
                    end
                end
                task.wait(0.25)
            else
                task.wait(0.5)
            end
        end
    end)

    Stoppers.FarmSelector = function()
        cancelFarmSearch()
        QuestRuntime.StopFarmSearch = nil
        World.onFarmMobRemoved = nil
        pcall(task.cancel, selectorWorker)
        for _, connection in ipairs(farmMobRowConnections) do connection:Disconnect() end
    end
end)

runSection("AutoSwords", function()
    local Materials = WorldBoss.Materials
    if not Materials then return end
    local Swords = {
        enabled={}, queue={}, generation=0, statuses={}, counts={}, toolSeen={}, npcSources={},
        blocked=setmetatable({}, {__mode="k"}), names=setmetatable({}, {__mode="k"}),
        dropCooldown=setmetatable({}, {__mode="k"}), nextSnapshot=0,
    }
    World.AutoSwords = Swords
    function World.confirmCombatTarget(model)
        if Motion.kind~="mob" or Motion.target~=model or not Motion.allowed(Motion.owner)
            or os.clock()>(Motion.lease or 0) or not World.liveMob(model) then return false end
        local selected=Motion.owner=="Swords" and QuestRuntime.SwordEnabled and Swords.target==model
            or Motion.owner=="Farm" and ((WorldBoss.Enabled and (WorldBoss.Target==model or WorldBoss.MaterialTarget==model))
                or (WorldBoss.IsMiniTarget and WorldBoss.IsMiniTarget(model)))
        if not selected then return false end
        for _,object in ipairs(model:GetDescendants()) do
            if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then return false end
        end
        return true
    end
    Swords.catalog = {
        {name="Dual Sword",rarity="Mythic",kind="craft"},
        {name="Crimson Sword",rarity="Legendary",kind="drop",source="Crimson King"},
        {name="Blunt Cleaver",rarity="Legendary",kind="drop",source="Overtime"},
        {name="Rapier",rarity="Legendary",kind="drop",source="Imperial Pro Player"},
    }
    Swords.sources = {
        ["Crimson King"]={name="Crimson King",SourceNames={"Crimson King"},island="West Island"},
        ["Overtime"]={name="Overtime",SourceNames={"Overtime","Overtime Sorcerer"},island="Sorcerers Island"},
        ["Imperial Pro Player"]={name="Imperial Pro Player",SourceNames={"Imperial Pro Player"},island="Online Island"},
        ["Emerald Swordsman"]={name="Emerald Swordsman",SourceNames={"Emerald Swordsman"},island="Online Island"},
        ["Old Fighter"]={name="Old Fighter",SourceNames={"Old Fighter","Master Roshi"},island="Good House"},
    }
    Swords.byName, Swords.known = {}, {}
    function Swords.key(value)
        local key=Materials.key(value)
        if key=="magicballs" then return "magicball" end
        return key
    end
    for _,entry in ipairs(Swords.catalog) do Swords.byName[entry.name]=entry;Swords.known[Swords.key(entry.name)]=entry.name end
    for _,name in ipairs({"Shadow Blade","Emerald Blade","Magic Ball","Dual Essence","Dual Orb"}) do
        Swords.known[Swords.key(name)]=name
    end
    for key in pairs(Swords.known) do WorldBoss.DropKeys[key]=true end

    function Swords.snapshot(force)
        local now=os.clock()
        if not force and now<Swords.nextSnapshot then return end
        Swords.nextSnapshot=now+0.8
        local tools,data,seen,gui={},{},{},{}
        local cash
        local moneyKeys={money=true,cash=true,beli=true,balance=true}
        local function numeric(value)
            if type(value)=="string" then
                local raw=value:gsub(",",""):gsub("%$",""):match("^%s*(.-)%s*$")
                local number=tonumber(raw)
                if number then return math.max(0,number) end
            end
            return Materials.number(value)
        end
        local function record(name,value)
            local key=Swords.key(name)
            local amount=numeric(value)
            if Swords.known[key] and amount~=nil then seen[key]=true;data[key]=math.max(data[key] or 0,amount) end
            if moneyKeys[key] and amount~=nil then cash=math.max(cash or 0,amount) end
        end
        for _,container in pairs({LocalPlayer:FindFirstChildOfClass("Backpack"),LocalPlayer.Character}) do
            if container and container.Parent then
                for _,tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") then
                        local key=Swords.key(tool.Name)
                        if not Swords.known[key] then key=Swords.key(tool.ToolTip) end
                        if not Swords.known[key] then
                            for field,value in pairs(tool:GetAttributes()) do
                                local fieldKey=Swords.key(field)
                                if fieldKey=="itemname" or fieldKey=="name" or fieldKey=="itemid" then
                                    local candidate=Swords.key(value)
                                    if Swords.known[candidate] then key=candidate;break end
                                end
                            end
                        end
                        if Swords.known[key] then
                            tools[key]=(tools[key] or 0)+(Materials.quantity(tool) or 1);Swords.toolSeen[key]=true
                        end
                    end
                end
            end
        end
        for field,value in pairs(LocalPlayer:GetAttributes()) do record(field,value) end
        for object in pairs(World.stats) do
            if object.Parent and object:IsDescendantOf(LocalPlayer) and not object:FindFirstAncestorWhichIsA("PlayerGui") then
                if object:IsA("ValueBase") then record(object.Name,object.Value)
                else
                    local amount=Materials.quantity(object)
                    if amount~=nil then record(object.Name,amount) end
                end
                if object:IsA("StringValue") and Materials.inInventory(object) then
                    local key=Swords.key(object.Value)
                    if Swords.known[key] then record(object.Value,Materials.quantity(object.Parent) or 1) end
                end
                for field,value in pairs(object:GetAttributes()) do record(field,value) end
            end
        end
        for object in pairs(World.gui) do
            if object.Parent and not object:IsDescendantOf(ScreenGui)
                and (object:IsA("TextLabel") or object:IsA("TextButton")) then
                if Materials.inInventory(object) then
                    local key=Swords.key(object.Text)
                    if Swords.known[key] then
                        local row=object.Parent
                        for _=1,3 do
                            if not row or row:IsA("ScreenGui") or row:IsA("PlayerGui") then break end
                            local amount=Materials.quantity(row)
                            if amount~=nil then gui[key]=math.max(gui[key] or 0,amount);break end
                            row=row.Parent
                        end
                    end
                elseif moneyKeys[Swords.key(object.Name)] then
                    local lower=object:GetFullName():lower()
                    if not lower:find("shop",1,true) and not lower:find("dialog",1,true) then record(object.Name,object.Text) end
                end
            end
        end
        Swords.counts={}
        for key in pairs(Swords.known) do
            local amount=math.max(tools[key] or 0,data[key] or 0)
            if amount==0 and not seen[key] and not Swords.toolSeen[key] then amount=gui[key] or 0 end
            Swords.counts[key]=amount
        end
        Swords.cash=cash
    end
    function Swords.count(name) return Swords.counts[Swords.key(name)] or 0 end
    function Swords.point(name)
        for _,point in ipairs(World.travelPoints or {}) do if point.name==name then return point.position end end
    end
    function Swords.fixedCamp(source)
        local names=source.SourceNames or {source.name}
        for _,name in ipairs(names) do
            local known=WorldBoss.MiniCamps and WorldBoss.MiniCamps[name]
            if known and not known.islandFallback and typeof(known.position)=="Vector3" then return known.position end
            local position=WorldBoss.DropCamps[name] or WorldBoss.Camp[name]
            if typeof(position)=="Vector3" then return position end
        end
        for _,recipe in pairs(WorldBoss.Requirements) do
            for _,name in ipairs(recipe.SourceNames or {}) do
                if table.find(names,name) and typeof(recipe.Position)=="Vector3" then return recipe.Position end
            end
        end
    end
    function Swords.camp(source)
        return Swords.fixedCamp(source) or source.lastPosition or Swords.point(source.island)
    end
    function Swords.missing(entry)
        if Swords.count(entry.name)>0 then return {} end
        if entry.kind=="drop" then return {entry.name.." (1)"} end
        local pending={}
        for _,name in ipairs({"Shadow Blade","Emerald Blade","Dual Essence"}) do
            if Swords.count(name)<1 then pending[#pending+1]=name.." (1)" end
        end
        local needsShadow=Swords.count("Shadow Blade")<1
        local balls=(needsShadow and 7 or 5)-Swords.count("Magic Ball")
        if balls>0 then pending[#pending+1]="Magic Ball ("..math.ceil(balls)..")" end
        local required=needsShadow and 60000 or 25000
        if Swords.cash==nil then pending[#pending+1]="Money (balance unavailable)"
        elseif Swords.cash<required then pending[#pending+1]="Money ($"..math.ceil(required-Swords.cash)..")" end
        return pending
    end
    function Swords.plan(entry)
        if Swords.count(entry.name)>0 then return {kind="done",item=entry.name} end
        if entry.kind=="drop" then return {kind="farm",item=entry.name,source=Swords.sources[entry.source]} end
        if Swords.count("Emerald Blade")<1 then return {kind="farm",item="Emerald Blade",source=Swords.sources["Emerald Swordsman"]} end
        local shadow=Swords.count("Shadow Blade")<1
        if Swords.count("Magic Ball")<(shadow and 7 or 5) then return {kind="farm",item="Magic Ball",source=Swords.sources["Old Fighter"]} end
        if Swords.cash~=nil and Swords.cash<(shadow and 60000 or 25000) then
            return {kind="farm",item="Money",source=Swords.sources["Old Fighter"]}
        end
        if shadow then return {kind="trade",item="Shadow Blade",npc="Shadow Swordsman",fee=35000,island="Online Island"} end
        if Swords.count("Dual Essence")<1 then return {kind="summon",item="Dual Essence"} end
        return {kind="trade",item="Dual Sword",npc="Master Blacksmith",fee=25000,island="Online Island"}
    end
    function Swords.status(entry,target)
        local label=Swords.statuses[entry.name]
        if not label or not label.Parent then return end
        local missing=Swords.missing(entry)
        local text="Target: "..(Swords.count(entry.name)>0 and "Obtained" or target or "None")
            .."\nMissing: "..(#missing>0 and table.concat(missing,", ") or "None")
        if label.Text~=text then label.Text=text end
    end
    function Swords.active(token)
        return not destroyed and token==Swords.generation and Swords.current~=nil and Swords.enabled[Swords.current]==true
    end
    function Swords.releaseTouch()
        if Swords.touch and type(firetouchinterest)=="function" then
            pcall(firetouchinterest,Swords.touch.root,Swords.touch.part,1)
        end
        Swords.touch=nil
    end
    function Swords.releaseInteraction()
        if Swords.heldPrompt then pcall(function() Swords.heldPrompt:InputHoldEnd() end);Swords.heldPrompt=nil end
        if Swords.mousePosition then
            local position=Swords.mousePosition
            pcall(function() VirtualInputManager:SendMouseButtonEvent(position.X,position.Y,0,false,game,0) end)
            pcall(function() VirtualUser:Button1Up(position,workspace.CurrentCamera.CFrame) end)
        end
        Swords.mousePosition=nil
        if Swords.ownsInteraction then
            if AcceptQuest.releaseGuiInput then AcceptQuest.releaseGuiInput() end
            QuestRuntime.Interacting=false;Swords.ownsInteraction=false
        end
        if Swords.hiddenHub then
            if not destroyed then ScreenGui.Enabled=Swords.restoreHub and uiOpen end
            Swords.hiddenHub,Swords.restoreHub=false,nil
        end
    end
    function Swords.releaseAssist()
        if not Swords.assist then return end
        if WorldBoss.Selected=="Dual Swordsman" then
            if WorldBoss.Enabled and WorldBoss.Stop then WorldBoss.Stop() end
            WorldBoss.Selected=Swords.savedBoss
            if WorldBoss.Refresh then WorldBoss.Refresh() end
        end
        Swords.assist,Swords.savedBoss=nil,nil
        QuestRuntime.SwordBossAssist=false
    end
    function Swords.clear()
        Swords.releaseInteraction();Swords.releaseTouch();Swords.releaseAssist()
        Motion.release("Swords")
        QuestRuntime.SwordEnabled=false
        Swords.current,Swords.target,Swords.targetSource,Swords.pickup=nil,nil,nil,nil
        Swords.routeSource,Swords.campVisited,Swords.islandVisited=nil,nil,nil
        Swords.pendingPurchase=nil
    end
    function Swords.matches(model,source)
        local cached=Swords.names[model]
        if cached and cached.source==source and cached.expires>os.clock() then return cached.valid end
        local function match(text)
            local raw=tostring(text or ""):gsub("%d+%s*/%s*%d+","")
            if Materials.matches(raw,source) then return true end
            return Materials.matches(raw:match("^[^\n]+") or raw,source)
        end
        local humanoid=getMobHumanoid(model)
        local valid=match(model.Name) or (humanoid and match(humanoid.DisplayName))
        for _,object in ipairs(model:GetDescendants()) do
            if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then valid=false;break end
            if object:IsA("TextLabel") and object:FindFirstAncestorWhichIsA("BillboardGui") and match(object.Text) then valid=true end
        end
        Swords.names[model]={source=source,valid=valid==true,expires=os.clock()+1}
        return valid==true
    end
    function Swords.findMob(source)
        local _,root=Motion.character()
        if not root then return nil end
        local winner,best=nil,math.huge
        for humanoid in pairs(World.humanoids) do
            local model=humanoid.Parent
            if model and model:IsA("Model") and model~=LocalPlayer.Character and not Players:GetPlayerFromCharacter(model)
                and model:IsDescendantOf(workspace) and not model:FindFirstAncestorWhichIsA("WorldModel")
                and not model:FindFirstAncestorWhichIsA("Camera") and Swords.matches(model,source) then
                local part=getMobRoot(model)
                if part then
                    source.lastPosition=part.Position
                    if humanoid.Health>0 and os.clock()>=(Swords.blocked[model] or 0) then
                        local distance=(part.Position-root.Position).Magnitude
                        if distance<best then winner,best=model,distance end
                    end
                end
            end
        end
        return winner
    end
    function Swords.stream(source)
        local now=os.clock()
        if now<(source.nextStream or 0) then return end
        source.nextStream=now+4
        local positions={Swords.camp(source)}
        for island in pairs(World.islands) do
            if island.Parent then
                local position=World.islandPosition(island)
                local port=Swords.point(source.island)
                if position and port and SafeMode.flatDistance(position,port)<1800 then
                    local parts=island:GetDescendants()
                    local step=math.max(1,math.ceil(#parts/12))
                    for i=1,#parts,step do if parts[i]:IsA("BasePart") then positions[#positions+1]=parts[i].Position end end
                end
            end
        end
        source.streamIndex=(source.streamIndex or 0)%math.max(1,#positions)+1
        local point=positions[source.streamIndex]
        if point then Motion.prepareStream(point) end
    end
    function Swords.farm(action)
        local source=action.source
        if Swords.routeSource~=source then Swords.routeSource,Swords.campVisited,Swords.islandVisited=source,false,false end
        local model=Swords.target
        if Swords.targetSource~=source or not World.liveMob(model) or not Swords.matches(model,source) then
            if model then Motion.release("Swords") end
            model=Swords.findMob(source)
            Swords.target,Swords.targetSource=model,source
            Swords.lastHealth,Swords.progressAt=model and getMobHumanoid(model).Health or nil,os.clock()
        end
        local point=Swords.fixedCamp(source)
        local _,root=Motion.character()
        if SafeMode.Enabled and root and not Swords.islandVisited then
            local port=Swords.point(source.island)
            local part=model and getMobRoot(model)
            if not port or SafeMode.flatDistance(root.Position,port)<=450
                or (part and SafeMode.flatDistance(root.Position,part.Position)<=300) then
                Swords.islandVisited=true
            else
                Swords.progressAt=os.clock()
                Motion.request("Swords",nil,0,"point",port)
                Swords.stream(source)
                return
            end
        end
        if point and root and not Swords.campVisited then
            local part=model and getMobRoot(model)
            if SafeMode.flatDistance(root.Position,point)<=20
                or (part and SafeMode.flatDistance(root.Position,part.Position)<=300) then
                Swords.campVisited=true
            else
                Swords.progressAt=os.clock()
                Motion.request("Swords",nil,0,"point",point)
                Swords.stream(source)
                return
            end
        end
        if model then
            local humanoid=getMobHumanoid(model)
            if humanoid.Health<(Swords.lastHealth or math.huge) then Swords.progressAt=os.clock() end
            Swords.lastHealth=humanoid.Health
            if os.clock()-(Swords.progressAt or os.clock())>45 then
                Swords.blocked[model]=os.clock()+15;Swords.target=nil;Motion.release("Swords");return
            end
            Motion.request("Swords",model,math.clamp(tonumber(farmDistance) or 1,1,10),"mob")
        else
            local point=Swords.camp(source)
            local _,root=Motion.character()
            if point and root then Motion.request("Swords",nil,0,"point",point)
            else Motion.release("Swords") end
            Swords.stream(source)
        end
    end
    function Swords.dropValid(object)
        if not object or not object.Parent or not object:IsDescendantOf(workspace) or World.held(object)
            or object:FindFirstAncestorWhichIsA("Camera") or object:FindFirstAncestorWhichIsA("WorldModel") then return false end
        local node=object
        while node and node~=workspace do
            if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return false end
            node=node.Parent
        end
        return true
    end
    function Swords.pickupStep(entry,root)
        local wanted={[Swords.key(entry.name)]=true}
        if entry.kind=="craft" then
            local required={ ["Shadow Blade"]=1,["Emerald Blade"]=1,["Dual Essence"]=1,
                ["Magic Ball"]=Swords.count("Shadow Blade")<1 and 7 or 5,
                ["Dual Orb"]=Swords.count("Dual Essence")<1 and 1 or 0 }
            for name,count in pairs(required) do if Swords.count(name)<count then wanted[Swords.key(name)]=true end end
        end
        local current=Swords.pickup
        if current and (not Swords.dropValid(current) or not wanted[Swords.key(WorldBoss.Drops[current] or current.Name)]
            or os.clock()>Swords.pickupUntil) then
            Swords.dropCooldown[current]=os.clock()+15;Swords.pickup=nil;Swords.releaseTouch();Motion.release("Swords");current=nil
        end
        if not current then
            local best=math.huge
            for object,key in pairs(WorldBoss.Drops) do
                if wanted[Swords.key(key)] and Swords.dropValid(object) and os.clock()>=(Swords.dropCooldown[object] or 0) then
                    local part=World.root(object)
                    if part then local distance=(part.Position-root.Position).Magnitude;if distance<best then current,best=object,distance end end
                end
            end
            if current then
                local timeout=SafeMode.Enabled and math.clamp(best/math.max(1,SafeMode.walkSpeed())+20,20,180) or 12
                Swords.pickup,Swords.pickupUntil,Swords.nextPickup=current,os.clock()+timeout,0
            end
        end
        if not current then return false end
        local part=World.root(current)
        if not part then Swords.pickup=nil;return false end
        Motion.request("Swords",part,0,"item")
        if (part.Position-root.Position).Magnitude<=5 and os.clock()>=(Swords.nextPickup or 0) then
            Swords.nextPickup=os.clock()+0.8
            local used=false
            for _,node in ipairs(current:GetDescendants()) do
                if node:IsA("ProximityPrompt") and node.Enabled then
                    if type(fireproximityprompt)=="function" then used=pcall(fireproximityprompt,node)
                    else used=World.emit(node.Triggered,LocalPlayer) end
                elseif node:IsA("ClickDetector") then
                    if type(fireclickdetector)=="function" then used=pcall(fireclickdetector,node)
                    else used=World.emit(node.MouseClick,LocalPlayer) end
                end
                if used then break end
            end
            if not used and type(firetouchinterest)=="function" then
                Swords.touch={root=root,part=part};pcall(firetouchinterest,root,part,0);task.wait(0.05);Swords.releaseTouch()
            end
            Swords.nextSnapshot=0
        end
        return true
    end
    function Swords.openNPC(npc,token)
        for _,object in ipairs(npc:GetDescendants()) do
            if object:IsA("ClickDetector") then
                if type(fireclickdetector)=="function" and pcall(fireclickdetector,object) then return true end
                if World.emit(object.MouseClick,LocalPlayer) then return true end
            elseif object:IsA("ProximityPrompt") and object.Enabled then
                if type(fireproximityprompt)=="function" and pcall(fireproximityprompt,object) then return true end
                if World.emit(object.Triggered,LocalPlayer) then return true end
                Swords.heldPrompt=object
                local okay=pcall(function() object:InputHoldBegin();task.wait(math.min(object.HoldDuration+0.05,2));object:InputHoldEnd() end)
                Swords.heldPrompt=nil
                if okay then return true end
            end
        end
        local camera=workspace.CurrentCamera
        local part=npc:FindFirstChild("Head",true) or getMobRoot(npc)
        if not camera or not part or not Swords.active(token) then return false end
        camera.CFrame=CFrame.lookAt(camera.CFrame.Position,part.Position)
        local point,visible=camera:WorldToViewportPoint(part.Position)
        if not visible or point.Z<=0 then return false end
        local position=Vector2.new(point.X,point.Y)
        Swords.restoreHub,Swords.hiddenHub=ScreenGui.Enabled,true;ScreenGui.Enabled=false
        Swords.mousePosition=position
        local okay=pcall(function()
            VirtualInputManager:SendMouseButtonEvent(position.X,position.Y,0,true,game,0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(position.X,position.Y,0,false,game,0)
        end)
        Swords.releaseInteraction()
        if Swords.active(token) then QuestRuntime.Interacting=true;Swords.ownsInteraction=true end
        return okay
    end
    function Swords.buttonText(button)
        local text=button:IsA("TextButton") and tostring(button.Text or "") or ""
        for _,child in ipairs(button:GetChildren()) do if child:IsA("TextLabel") then text=text.." "..child.Text end end
        return text:lower():gsub("<[^>]*>","")
    end
    function Swords.option(action,before,selected)
        local best,score=nil,0
        for button in pairs(World.gui) do
            if button.Parent and button:IsA("GuiButton") and button.Active~=false and AcceptQuest.visible(button)
                and not button:IsDescendantOf(ScreenGui) and not Materials.inInventory(button) then
                local label=Swords.buttonText(button)
                local key=Swords.key(label)
                local banned=label:find("robux",1,true) or label:find("r$",1,true) or label:find("gamepass",1,true)
                    or label:find("sell",1,true) or label:find("discard",1,true) or label:find("delete",1,true) or label:find("gift",1,true)
                    or key=="cancel" or key=="close" or key=="no" or key=="decline"
                local context=""
                local node=button.Parent
                for _=1,3 do
                    if not node or node:IsA("PlayerGui") then break end
                    for i,child in ipairs(node:GetDescendants()) do
                        if i>70 then break end
                        if child:IsA("TextLabel") or child:IsA("TextButton") then context=context.." "..tostring(child.Text or "") end
                    end
                    if Swords.key(context):find(Swords.key(action.item),1,true) then break end
                    node=node.Parent
                end
                local contextual=Swords.key(context):find(Swords.key(action.item),1,true)~=nil
                local candidate=0
                if not banned and key:find(Swords.key(action.item),1,true) then candidate=100
                elseif not banned and contextual and (selected or not before[button]) then
                    if key=="sure" or key=="yes" or key=="confirm" or key=="craft" or key=="buy" or key=="purchase"
                        or tonumber(label:gsub("[^%d]",""))==action.fee then candidate=65 end
                end
                if candidate>score then best,score=button,candidate end
            end
        end
        return best,score
    end
    function Swords.trade(action,token)
        if os.clock()<(Swords.nextTrade or 0) then return end
        local source=Swords.npcSources[action.npc]
        if not source then source={name=action.npc,island=action.island};Swords.npcSources[action.npc]=source end
        local npc=source.npc
        if not npc or not npc.Parent or not npc:IsDescendantOf(workspace) then
            npc=nil
            if os.clock()>=(source.nextLookup or 0) then source.nextLookup=os.clock()+1;source.npc=WorldBoss.FindNPC(action.npc);npc=source.npc end
        end
        local _,root=Motion.character()
        if not npc then
            local point=Swords.point(action.island)
            if point and root then Motion.request("Swords",nil,0,"point",point)
            else Motion.release("Swords") end
            Swords.stream(source)
            return
        end
        if not Motion.request("Swords",npc,4,"giver") or not Motion.arrived then return end
        local part=getMobRoot(npc)
        if not root or not part or (part.Position-root.Position).Magnitude>14 then return end
        if QuestRuntime.Interacting or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy then return end
        Swords.nextTrade=os.clock()+10
        local before={}
        for button in pairs(World.gui) do if button.Parent and button:IsA("GuiButton") and AcceptQuest.visible(button) then before[button]=true end end
        QuestRuntime.Interacting,Swords.ownsInteraction=true,true
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
        local opened=Swords.openNPC(npc,token)
        local used,selected=setmetatable({}, {__mode="k"}),false
        local deadline=os.clock()+7
        while opened and Swords.active(token) and os.clock()<deadline do
            Swords.snapshot(true)
            if Swords.count(action.item)>0 then break end
            local button,score=Swords.option(action,before,selected)
            if button and not used[button] then
                used[button]=true
                if AcceptQuest.activateButton(button) then
                    selected=selected or score==100
                    Swords.pendingPurchase={item=action.item,untilTime=os.clock()+4}
                    task.wait(0.5)
                else task.wait(0.3) end
            else task.wait(0.25) end
        end
        Swords.releaseInteraction();Swords.nextSnapshot=0
    end
    function Swords.assistStep()
        if Swords.assist then
            if WorldBoss.Selected~="Dual Swordsman" or not WorldBoss.Enabled then Swords.releaseAssist() end
            return
        end
        if WorldBoss.Enabled then return end
        Motion.release("Swords")
        Swords.savedBoss, Swords.assist=WorldBoss.Selected,true
        QuestRuntime.SwordBossAssist=true
        WorldBoss.Selected="Dual Swordsman"
        WorldBoss.Start()
    end
    function Swords.tick(token)
        Swords.snapshot()
        local entry=Swords.current and Swords.byName[Swords.current]
        if not entry or not Swords.enabled[entry.name] or Swords.count(entry.name)>0 then
            Swords.clear()
            for _,name in ipairs(Swords.queue) do
                local candidate=Swords.byName[name]
                if Swords.enabled[name] and Swords.count(name)<1 then entry=candidate;Swords.current=name;break end
            end
        end
        for _,candidate in ipairs(Swords.catalog) do
            Swords.status(candidate)
        end
        if not Swords.current or not entry then return end
        local action=Swords.plan(entry)
        local text=action.item..(action.source and " - "..action.source.name or action.npc and " - "..action.npc or "")
        Swords.status(entry,text)
        if WorldBoss.Enabled and not Swords.assist then
            QuestRuntime.SwordEnabled=false;Motion.release("Swords");return
        end
        QuestRuntime.SwordEnabled=true
        if autoQuestEnabled or QuestRuntime.FruitBuying or QuestRuntime.ItemBusy or QuestRuntime.AcceptanceMoving
            or (QuestRuntime.Interacting and not Swords.ownsInteraction) then
            QuestRuntime.SwordEnabled=false;Motion.release("Swords");return
        end
        if action.kind~="summon" then Swords.releaseAssist() end
        if not Motion.allowed("Swords") and action.kind~="summon" then return end
        local _,root=Motion.character()
        if not root then Motion.release("Swords");return end
        if Swords.pendingPurchase and Swords.count(Swords.pendingPurchase.item)==0
            and os.clock()<Swords.pendingPurchase.untilTime then return end
        Swords.pendingPurchase=nil
        if action.kind~="summon" and Swords.pickupStep(entry,root) then return end
        if action.kind=="farm" then Swords.farm(action)
        elseif action.kind=="trade" then Swords.target=nil;Swords.trade(action,token)
        elseif action.kind=="summon" then Swords.target=nil;Swords.assistStep() end
    end
    function Swords.setEnabled(name,enabled)
        if not Swords.byName[name] then return end
        Swords.generation=Swords.generation+1
        if Swords.worker then pcall(task.cancel,Swords.worker);Swords.worker=nil end
        Swords.clear()
        Swords.enabled[name]=enabled==true
        if enabled and not table.find(Swords.queue,name) then Swords.queue[#Swords.queue+1]=name end
        local any=false
        for _,state in pairs(Swords.enabled) do if state then any=true;break end end
        if not any then
            Swords.snapshot(true);for _,entry in ipairs(Swords.catalog) do Swords.status(entry) end
            return
        end
        local token=Swords.generation
        Swords.worker=task.spawn(function()
            for i,object in ipairs(workspace:GetDescendants()) do
                if destroyed or token~=Swords.generation then return end
                World.indexSummonDrop(object)
                if i%250==0 then task.wait() end
            end
            while not destroyed and token==Swords.generation do
                local okay,err=pcall(Swords.tick,token)
                if not okay then
                    Swords.clear()
                    local entry=Swords.byName[name]
                    if entry then Swords.status(entry,"Paused; retrying") end
                    if os.clock()>=(Swords.warnAt or 0) then warn("[Random Hub | Auto Sword] "..tostring(err));Swords.warnAt=os.clock()+10 end
                end
                task.wait(Swords.current and 0.3 or 1)
            end
        end)
    end
    Swords.snapshot(true)
    for index,entry in ipairs(Swords.catalog) do
        local current=entry
        local _,_,card=createCombatToggle(Pages.AutoItems,"AutoSword_"..Swords.key(entry.name),"Auto Sword: "..entry.name,index+1,function(state)
            Swords.setEnabled(current.name,state)
        end)
        card.Size=UDim2.new(1,0,0,0)
        card.AutomaticSize=Enum.AutomaticSize.Y
        card:FindFirstChild("ClickArea").Size=UDim2.new(1,0,0,44)
        card:FindFirstChildWhichIsA("TextLabel").Size=UDim2.new(1,-110,0,44)
        card:FindFirstChild("Toggle").Position=UDim2.new(1,-68,0,8)
        local padding=Instance.new("UIPadding")
        padding.PaddingBottom=UDim.new(0,8)
        padding.Parent=card
        local label=Instance.new("TextLabel")
        label.Name="SwordStatus_"..Swords.key(entry.name)
        label.Position=UDim2.fromOffset(16,44);label.Size=UDim2.new(1,-32,0,0)
        label.AutomaticSize=Enum.AutomaticSize.Y
        label.BackgroundTransparency=1;label.TextColor3=Theme.TextDim;label.Font=Enum.Font.Gotham
        label.TextSize=11;label.TextWrapped=true;label.TextXAlignment=Enum.TextXAlignment.Left;label.TextYAlignment=Enum.TextYAlignment.Top
        label.ZIndex=3;label.Parent=card;Swords.statuses[entry.name]=label
        Swords.status(entry)
    end
    Stoppers.Swords=function()
        Swords.generation=Swords.generation+1
        if Swords.worker then pcall(task.cancel,Swords.worker);Swords.worker=nil end
        table.clear(Swords.enabled);Swords.clear()
    end
end)


runSection("AutoStats", function()
    local page = Pages.AutoStats
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    local attributes = {
        {key = "strength", title = "Strength", text = "Auto Point Strength"},
        {key = "defense", title = "Defense", text = "Auto Point Defense"},
        {key = "stamina", title = "Stamina", text = "Auto Point Stamina"},
        {key = "sword", title = "Sword", text = "Auto Point Sword"},
        {key = "devilfruit", title = "Devil Fruit", text = "Auto Point Devil Fruit"},
    }
    local selected = {}
    local buttons = {}
    local invalidated = true
    local scanAt = 0
    local warningAt = -math.huge
    local workerToken = 0
    local worker = nil
    local cursor = 0
    local pointValue = nil
    local nextPointSearch = 0
    local pointsPerBatch = 1
    local batchTarget = nil
    local batchRemaining = 0

    -- Quantidade de pontos por ciclo do atributo selecionado.
    local BatchCard = createStyledCard(page, "AutoStatsPointsPerBatchCard", 56, 1)
    local BatchTitle = Instance.new("TextLabel")
    BatchTitle.Name = "AutoStatsPointsPerBatchTitle"
    BatchTitle.Size = UDim2.new(1, -132, 0, 26)
    BatchTitle.Position = UDim2.fromOffset(16, 12)
    BatchTitle.BackgroundTransparency = 1
    BatchTitle.Text = "Amount of Points"
    BatchTitle.TextColor3 = Theme.Text
    BatchTitle.Font = Enum.Font.GothamBold
    BatchTitle.TextSize = 14
    BatchTitle.TextXAlignment = Enum.TextXAlignment.Left
    BatchTitle.Parent = BatchCard

    local BatchInput = Instance.new("TextBox")
    BatchInput.Name = "AutoStatsPointsPerBatchInput"
    BatchInput.Size = UDim2.fromOffset(86, 34)
    BatchInput.Position = UDim2.new(1, -102, 0, 8)
    BatchInput.BackgroundColor3 = Theme.BgSecondary
    BatchInput.BorderSizePixel = 0
    BatchInput.ClearTextOnFocus = false
    BatchInput.Text = tostring(pointsPerBatch)
    BatchInput.PlaceholderText = "1-1000"
    BatchInput.TextColor3 = Theme.Text
    BatchInput.Font = Enum.Font.GothamBold
    BatchInput.TextSize = 16
    BatchInput.TextXAlignment = Enum.TextXAlignment.Center
    BatchInput.Parent = BatchCard
    addCorner(BatchInput, 9)
    addStroke(BatchInput, Theme.Accent2, 1, 0.4)

    connect(BatchInput.FocusLost, function()
        local raw = tonumber(BatchInput.Text)
        if raw and raw == raw and raw > 0 and raw < math.huge then
            pointsPerBatch = math.clamp(math.floor(raw), 1, 1000)
        end
        BatchInput.Text = tostring(pointsPerBatch)
        batchTarget, batchRemaining = nil, 0
    end)

    local function normalize(value)
        return tostring(value or ""):lower():gsub("<[^>]*>", "")
            :gsub("[^%a%d]", "")
    end

    local validNames = {}
    for _, entry in ipairs(attributes) do validNames[entry.key] = true end

    local function textKey(node)
        if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
            return normalize(node.Text)
        end
        return ""
    end

    local function isStatTitle(node, key)
        return node and node.Parent and textKey(node) == key and validNames[key] == true
    end

    local function usableButton(button)
        if not button:IsA("GuiButton") or not button.Parent or button:IsDescendantOf(ScreenGui) then return false end
        local label = normalize(button.Name .. " " .. (button:IsA("TextButton") and button.Text or ""))
        if label:find("reset", 1, true) or label:find("minus", 1, true)
            or label:find("remove", 1, true) or label:find("subtract", 1, true)
            or label:find("close", 1, true) then return false end
        return true
    end

    local function buttonScore(button)
        if not usableButton(button) then return -1 end
        local text = button:IsA("TextButton") and button.Text or ""
        local name = normalize(button.Name)
        if text:match("^%s*%+%s*$") or text:match("^%s*＋%s*$") then return 100 end
        if name:find("plus", 1, true) or name:find("add", 1, true)
            or name:find("upgrade", 1, true) or name:find("increase", 1, true) then return 90 end
        for _, child in ipairs(button:GetDescendants()) do
            if child:IsA("TextLabel") and tostring(child.Text):match("^%s*%+%s*$") then return 95 end
        end
        if button:IsA("ImageButton") then return 45 end
        if name == "button" or name == "textbutton" then return 20 end
        return -1
    end

    local function rowButton(label, key)
        local parent = label.Parent
        local depth = 0
        local center = label.AbsolutePosition + label.AbsoluteSize / 2
        while parent and parent ~= playerGui and depth < 6 do
            if parent:IsA("GuiObject") then
                local descendants = parent:GetDescendants()
                local hasOtherStat = false
                for _, child in ipairs(descendants) do
                    if child ~= label and isStatTitle(child, textKey(child)) then
                        hasOtherStat = true
                        break
                    end
                end
                if hasOtherStat then break end
                local best, score = nil, -math.huge
                for _, child in ipairs(descendants) do
                    if child:IsA("GuiButton") then
                        local quality = buttonScore(child)
                        if quality >= 20 then
                            local buttonCenter = child.AbsolutePosition + child.AbsoluteSize / 2
                            local dx, dy = buttonCenter.X - center.X, math.abs(buttonCenter.Y - center.Y)
                            if dx >= -8 and dy <= math.max(55, label.AbsoluteSize.Y * 2) then
                                local weighted = quality + math.min(15, math.max(dx, 0) / 20) - dy / 5
                                if weighted > score then best, score = child, weighted end
                            end
                        end
                    end
                end
                if best then return best end
            end
            parent, depth = parent.Parent, depth + 1
        end
        return nil
    end

    local function refreshButtons(now)
        if not playerGui or not playerGui.Parent then
            playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then return end
            invalidated = true
        end
        if now < scanAt then return end
        if not invalidated and next(buttons) then return end
        invalidated = false
        scanAt = now + 3
        local found = {}
        for _, node in ipairs(playerGui:GetDescendants()) do
            if node:IsA("TextLabel") or node:IsA("TextButton") then
                local key = textKey(node)
                if validNames[key] and not found[key] then
                    local button = rowButton(node, key)
                    if button then found[key] = button end
                end
            end
        end
        buttons = found
    end

    local function availablePoints()
        if pointValue and pointValue.Parent then
            return math.max(0, tonumber(pointValue.Value) or 0)
        end
        pointValue = nil
        local now = os.clock()
        if now < nextPointSearch then return nil end
        nextPointSearch = now + 5
        local pointKeys = {
            statpoints = true, statspoints = true, unspentpoints = true,
            unspentstatpoints = true, availablepoints = true,
            availablepointsstats = true, skillpoints = true, pointsavailable = true,
        }
        local holders = {LocalPlayer}
        for _, name in ipairs({"leaderstats", "Data", "Stats"}) do
            local holder = LocalPlayer:FindFirstChild(name)
            if holder then holders[#holders + 1] = holder end
        end
        for _, holder in ipairs(holders) do
            if holder then
                local ok, attrs = pcall(function() return holder:GetAttributes() end)
                if ok then
                    for name, value in pairs(attrs) do
                        if pointKeys[normalize(name)] and tonumber(value) then
                            return math.max(0, tonumber(value))
                        end
                    end
                end
            end
        end
        for _, container in ipairs(LocalPlayer:GetChildren()) do
            if container ~= playerGui and container ~= LocalPlayer.Character
                and not container:IsA("Backpack") and not container:IsA("PlayerScripts") then
                for _, node in ipairs(container:GetDescendants()) do
                    if node:IsA("IntValue") or node:IsA("NumberValue") then
                        if pointKeys[normalize(node.Name)] then
                            pointValue = node
                            return math.max(0, tonumber(node.Value) or 0)
                        end
                    end
                end
            end
        end
        return nil
    end

    local function emitButton(button)
        if World.emit(button.MouseButton1Click) or World.emit(button.Activated, nil, 1) then return true end
        -- Native mouse fallback only when a stats window is already visible; do not open one.
        local ancestor = button
        while ancestor and ancestor ~= playerGui do
            if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
            if ancestor:IsA("LayerCollector") and not ancestor.Enabled then return false end
            ancestor = ancestor.Parent
        end
        if type(VirtualInputManager) ~= "nil" and VirtualInputManager then
            local center = button.AbsolutePosition + button.AbsoluteSize / 2
            local hubPosition, hubSize = Main.AbsolutePosition, Main.AbsoluteSize
            local obscured = ScreenGui.Enabled and center.X >= hubPosition.X and center.X <= hubPosition.X + hubSize.X
                and center.Y >= hubPosition.Y and center.Y <= hubPosition.Y + hubSize.Y
            if button.AbsoluteSize.X > 0 and button.AbsoluteSize.Y > 0 and center.X >= 0 and center.Y >= 0 and not obscured then
                return pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    task.wait(0.035)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                end)
            end
        end
        return false
    end

    local function nextSelected()
        for step = 1, #attributes do
            local index = (cursor + step - 1) % #attributes + 1
            local key = attributes[index].key
            if selected[key] then
                cursor = index
                return key
            end
        end
    end

    local function tick(token)
        local now = os.clock()
        if not playerGui or not playerGui.Parent then return 2 end
        refreshButtons(now)
        local remaining = availablePoints()
        if remaining ~= nil and remaining < 1 then return 1.5 end
        if not batchTarget or not selected[batchTarget] or batchRemaining <= 0 then
            batchTarget = nextSelected()
            batchRemaining = pointsPerBatch
        end
        local key = batchTarget
        if not key then return 2 end
        local button = buttons[key]
        if not button or not button.Parent or not button:IsDescendantOf(playerGui) then
            invalidated = true
            return 3
        end
        -- Blocos limitados reduzem travamentos e permitem cancelar imediatamente.
        -- Cada acionamento corresponde a uma tentativa de gastar um ponto.
        local count = math.min(batchRemaining, 15, remaining or batchRemaining)
        if count < 1 then return 1.5 end
        for attempt = 1, count do
            if destroyed or workerToken ~= token or not selected[key] then return 0.2 end
            if not button.Parent or not button:IsDescendantOf(playerGui) then
                invalidated = true
                return 3
            end
            if not emitButton(button) then
                if os.clock() - warningAt > 30 then
                    warningAt = os.clock()
                    warn("[Random Hub | Auto Stats] O executor nao permite acionar o botao '+' com a interface fechada.")
                end
                return 3
            end
            batchRemaining = batchRemaining - 1
            if attempt < count then task.wait(0.09) end
        end
        if batchRemaining <= 0 then batchTarget = nil end
        return remaining ~= nil and 0.45 or 1.2
    end

    local function stopWorker()
        workerToken = workerToken + 1
        if worker then pcall(task.cancel, worker); worker = nil end
    end

    local function updateWorker()
        stopWorker()
        if destroyed or not next(selected) then return end
        local token = workerToken
        worker = task.spawn(function()
            while not destroyed and workerToken == token and next(selected) do
                local ok, delay = pcall(tick, token)
                if not ok and os.clock() - warningAt > 30 then
                    warningAt = os.clock()
                    warn("[Random Hub | Auto Stats] " .. tostring(delay))
                end
                task.wait(ok and delay or 2)
            end
        end)
    end

    for index, entry in ipairs(attributes) do
        local key = entry.key
        createCombatToggle(page, "AutoStat_" .. key, entry.text, index + 1, function(state)
            selected[key] = state == true or nil
            batchTarget, batchRemaining = nil, 0
            invalidated, scanAt = true, 0
            updateWorker()
        end)
    end

    if playerGui then
        connect(playerGui.DescendantAdded, function(node)
            if node:IsA("TextLabel") or node:IsA("GuiButton") then invalidated = true end
        end)
        connect(playerGui.DescendantRemoving, function(node)
            if node:IsA("TextLabel") or node:IsA("GuiButton") then invalidated = true end
        end)
    end
    Stoppers.AutoStats = function()
        stopWorker()
        table.clear(selected)
        table.clear(buttons)
    end
end)

runSection("Config", function()
    local ConfigPage = Pages.Config

    local ScaleCard = createStyledCard(ConfigPage, "UIScaleCard", 96, 1)
    local ScaleTitle = Instance.new("TextLabel")
    ScaleTitle.Name = "ScaleTitle"
    ScaleTitle.Size = UDim2.new(1, -110, 0, 24)
    ScaleTitle.Position = UDim2.fromOffset(16, 8)
    ScaleTitle.BackgroundTransparency = 1
    ScaleTitle.Text = "UI Scale"
    ScaleTitle.TextColor3 = Theme.Text
    ScaleTitle.Font = Enum.Font.GothamBold
    ScaleTitle.TextSize = 14
    ScaleTitle.TextXAlignment = Enum.TextXAlignment.Left
    ScaleTitle.Parent = ScaleCard
    local ScaleValue = Instance.new("TextLabel")
    ScaleValue.Name = "ScaleValue"
    ScaleValue.Size = UDim2.fromOffset(70, 24)
    ScaleValue.Position = UDim2.new(1, -86, 0, 8)
    ScaleValue.BackgroundTransparency = 1
    ScaleValue.Text = "100%"
    ScaleValue.TextColor3 = Theme.Accent2
    ScaleValue.Font = Enum.Font.GothamBold
    ScaleValue.TextSize = 13
    ScaleValue.TextXAlignment = Enum.TextXAlignment.Right
    ScaleValue.Parent = ScaleCard

    local ScaleTrack = Instance.new("TextButton")
    ScaleTrack.Name = "ScaleTrack"
    ScaleTrack.Size = UDim2.new(1, -32, 0, 8)
    ScaleTrack.Position = UDim2.fromOffset(16, 50)
    ScaleTrack.BackgroundColor3 = Theme.BgSecondary
    ScaleTrack.BorderSizePixel = 0
    ScaleTrack.Text = ""
    ScaleTrack.AutoButtonColor = false
    ScaleTrack.Parent = ScaleCard
    addCorner(ScaleTrack, 4)
    local ScaleFill = Instance.new("Frame")
    ScaleFill.Name = "ScaleFill"
    ScaleFill.Size = UDim2.new((CONFIG.UIScale - 0.7) / 0.6, 0, 1, 0)
    ScaleFill.BackgroundColor3 = Theme.Accent2
    ScaleFill.BorderSizePixel = 0
    ScaleFill.Parent = ScaleTrack
    addCorner(ScaleFill, 4)
    local ScaleKnob = Instance.new("Frame")
    ScaleKnob.Name = "ScaleKnob"
    ScaleKnob.Size = UDim2.fromOffset(18, 18)
    ScaleKnob.Position = UDim2.new((CONFIG.UIScale - 0.7) / 0.6, -9, 0.5, -9)
    ScaleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ScaleKnob.BorderSizePixel = 0
    ScaleKnob.Parent = ScaleTrack
    addCorner(ScaleKnob, 9)
    addStroke(ScaleKnob, Theme.Accent2, 1, 0.1)
    local draggingScale = false

    local function applyUIScaleFromX(screenX)
        local width = ScaleTrack.AbsoluteSize.X
        if width <= 0 then return end
        local relative = math.clamp((screenX - ScaleTrack.AbsolutePosition.X) / width, 0, 1)
        local raw = 0.7 + relative * 0.6
        local scale = math.clamp(math.floor(raw * 20 + 0.5) / 20, 0.7, 1.3)
        CONFIG.UIScale = scale
        MainScale.Scale = scale
        ScaleValue.Text = tostring(math.floor(scale * 100 + 0.5)) .. "%"
        local fraction = (scale - 0.7) / 0.6
        ScaleFill.Size = UDim2.new(fraction, 0, 1, 0)
        ScaleKnob.Position = UDim2.new(fraction, -9, 0.5, -9)
        if uiOpen then
            Main.Position = getScaledWindowOffset()
        else
            Main.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    connect(ScaleTrack.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingScale = true
            applyUIScaleFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if draggingScale and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            applyUIScaleFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingScale = false
        end
    end)

    local antiAfkEnabled = false
    local antiAfkWorker
    local function stopAntiAfk()
        antiAfkEnabled = false
        if antiAfkWorker then pcall(task.cancel, antiAfkWorker); antiAfkWorker = nil end
        if QuestRuntime.ReleaseAttack then QuestRuntime.ReleaseAttack() end
    end
    local setAntiAfk = createCombatToggle(ConfigPage, "AntiAfkToggleCard", "Anti AFK", 5, function(state)
        stopAntiAfk()
        antiAfkEnabled = state == true
        if not antiAfkEnabled then return end
        antiAfkWorker = task.spawn(function()
            while antiAfkEnabled and not destroyed do
                task.wait(300)
                if antiAfkEnabled and not destroyed and not QuestRuntime.Interacting and not QuestRuntime.AcceptanceMoving and not QuestRuntime.FruitBuying and not QuestRuntime.ItemBusy then
                    pcall(combatAutoAttackClickOffscreen)
                end
            end
        end)
    end)
    -- Comeca ligado e continua podendo ser desligado pelo toggle normalmente.
    setAntiAfk(true)
    Stoppers.AntiAfk = stopAntiAfk
    createCombatToggle(ConfigPage, "FPSBoostToggleCard", "FPS Boost", 6, Graphics.setEnabled)
    createCombatToggle(ConfigPage, "SafeModeToggleCard", "Safe Mode", 7, SafeMode.setEnabled)

    local FarmDistanceCard = createStyledCard(ConfigPage, "FarmDistanceCard", 96, 2)
    local FarmDistanceTitle = Instance.new("TextLabel")
    FarmDistanceTitle.Name = "FarmDistanceTitle"
    FarmDistanceTitle.Size = UDim2.new(1, -120, 0, 24)
    FarmDistanceTitle.Position = UDim2.fromOffset(16, 8)
    FarmDistanceTitle.BackgroundTransparency = 1
    FarmDistanceTitle.Text = "Distance from NPC"
    FarmDistanceTitle.TextColor3 = Theme.Text
    FarmDistanceTitle.Font = Enum.Font.GothamBold
    FarmDistanceTitle.TextSize = 14
    FarmDistanceTitle.TextXAlignment = Enum.TextXAlignment.Left
    FarmDistanceTitle.Parent = FarmDistanceCard

    local FarmDistanceValue = Instance.new("TextLabel")
    FarmDistanceValue.Name = "FarmDistanceValue"
    FarmDistanceValue.Size = UDim2.fromOffset(95, 24)
    FarmDistanceValue.Position = UDim2.new(1, -111, 0, 8)
    FarmDistanceValue.BackgroundTransparency = 1
    FarmDistanceValue.Text = string.format("%.1f studs", farmDistance)
    FarmDistanceValue.TextColor3 = Theme.Accent2
    FarmDistanceValue.Font = Enum.Font.GothamBold
    FarmDistanceValue.TextSize = 13
    FarmDistanceValue.TextXAlignment = Enum.TextXAlignment.Right
    FarmDistanceValue.Parent = FarmDistanceCard

    local FarmDistanceTrack = Instance.new("TextButton")
    FarmDistanceTrack.Name = "FarmDistanceTrack"
    FarmDistanceTrack.Size = UDim2.new(1, -32, 0, 8)
    FarmDistanceTrack.Position = UDim2.fromOffset(16, 50)
    FarmDistanceTrack.BackgroundColor3 = Theme.BgSecondary
    FarmDistanceTrack.BorderSizePixel = 0
    FarmDistanceTrack.Text = ""
    FarmDistanceTrack.AutoButtonColor = false
    FarmDistanceTrack.Parent = FarmDistanceCard
    addCorner(FarmDistanceTrack, 4)

    local FarmDistanceFill = Instance.new("Frame")
    FarmDistanceFill.Name = "FarmDistanceFill"
    FarmDistanceFill.Size = UDim2.new((farmDistance - 1) / 9, 0, 1, 0)
    FarmDistanceFill.BackgroundColor3 = Theme.Accent2
    FarmDistanceFill.BorderSizePixel = 0
    FarmDistanceFill.Parent = FarmDistanceTrack
    addCorner(FarmDistanceFill, 4)

    local FarmDistanceKnob = Instance.new("Frame")
    FarmDistanceKnob.Name = "FarmDistanceKnob"
    FarmDistanceKnob.Size = UDim2.fromOffset(18, 18)
    FarmDistanceKnob.Position = UDim2.new((farmDistance - 1) / 9, -9, 0.5, -9)
    FarmDistanceKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    FarmDistanceKnob.BorderSizePixel = 0
    FarmDistanceKnob.Parent = FarmDistanceTrack
    addCorner(FarmDistanceKnob, 9)
    addStroke(FarmDistanceKnob, Theme.Accent2, 1, 0.1)

    local function applyFarmDistanceFromX(screenX)
        local width = FarmDistanceTrack.AbsoluteSize.X
        if width <= 0 then return end
        local relative = math.clamp((screenX - FarmDistanceTrack.AbsolutePosition.X) / width, 0, 1)
        local rawDistance = 1 + relative * 9
        farmDistance = math.clamp(math.floor(rawDistance * 2 + 0.5) / 2, 1, 10)
        local fraction = (farmDistance - 1) / 9
        FarmDistanceValue.Text = string.format("%.1f studs", farmDistance)
        FarmDistanceFill.Size = UDim2.new(fraction, 0, 1, 0)
        FarmDistanceKnob.Position = UDim2.new(fraction, -9, 0.5, -9)
    end

    local draggingFarmDistance = false
    connect(FarmDistanceTrack.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingFarmDistance = true
            applyFarmDistanceFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if draggingFarmDistance and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            applyFarmDistanceFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingFarmDistance = false
        end
    end)

    --// Voo manual independente dos sistemas de Auto Farm / TP.
    -- A instancia de LinearVelocity so existe enquanto o toggle estiver ligado.
    local RunService = game:GetService("RunService")
    local FLIGHT_ZERO = Vector3.new(0, 0, 0)

    local function clearManualFlight()
        if ManualFlight.velocity then
            ManualFlight.velocity:Destroy()
            ManualFlight.velocity = nil
        end
        if ManualFlight.attachment then
            ManualFlight.attachment:Destroy()
            ManualFlight.attachment = nil
        end
        if ManualFlight.root and ManualFlight.root.Parent then
            ManualFlight.root.AssemblyLinearVelocity = FLIGHT_ZERO
            ManualFlight.root.AssemblyAngularVelocity = FLIGHT_ZERO
        end
        local humanoid = ManualFlight.humanoid
        if humanoid and humanoid.Parent then
            if ManualFlight.savedPlatformStand ~= nil then
                humanoid.PlatformStand = ManualFlight.savedPlatformStand
            end
            if ManualFlight.savedAutoRotate ~= nil then
                humanoid.AutoRotate = ManualFlight.savedAutoRotate
            end
            if humanoid.Health > 0 and not humanoid.PlatformStand then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        ManualFlight.root, ManualFlight.humanoid = nil, nil
        ManualFlight.savedPlatformStand, ManualFlight.savedAutoRotate = nil, nil
        ManualFlight.liftUntil = nil
    end

    local function attachManualFlight(root, humanoid)
        if ManualFlight.root == root and ManualFlight.velocity and ManualFlight.velocity.Parent == root then
            return
        end
        clearManualFlight()
        ManualFlight.root, ManualFlight.humanoid = root, humanoid
        ManualFlight.savedPlatformStand = humanoid.PlatformStand
        ManualFlight.savedAutoRotate = humanoid.AutoRotate
        humanoid.AutoRotate = false
        humanoid.PlatformStand = true
        local attachment = Instance.new("Attachment")
        attachment.Name = "RandomHubManualFlyAttachment"
        attachment.Parent = root
        ManualFlight.attachment = attachment
        local velocity = Instance.new("LinearVelocity")
        velocity.Name = "RandomHubManualFlyVelocity"
        velocity.Attachment0 = attachment
        velocity.RelativeTo = Enum.ActuatorRelativeTo.World
        velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        velocity.ForceLimitsEnabled = false
        velocity.VectorVelocity = Vector3.new(0, math.min(ManualFlight.Speed, 18), 0)
        velocity.Parent = root
        ManualFlight.velocity = velocity
        ManualFlight.liftUntil = os.clock() + 0.35
    end

    local function keyHeld(key)
        return UserInputService:IsKeyDown(key)
    end

    local function updateManualFlight()
        if not ManualFlight.Enabled or destroyed then return end
        local character, root, humanoid = Motion.character()
        if not character then
            if ManualFlight.root then clearManualFlight() end
            return
        end
        if root ~= ManualFlight.root or not ManualFlight.velocity or not ManualFlight.velocity.Parent then
            attachManualFlight(root, humanoid)
        end
        if UserInputService:GetFocusedTextBox() then
            ManualFlight.velocity.VectorVelocity = FLIGHT_ZERO
            return
        end
        local camera = workspace.CurrentCamera
        local look = camera and camera.CFrame.LookVector or root.CFrame.LookVector
        local right = camera and camera.CFrame.RightVector or root.CFrame.RightVector
        look = Vector3.new(look.X, 0, look.Z)
        right = Vector3.new(right.X, 0, right.Z)
        look = look.Magnitude > 0.001 and look.Unit or Vector3.new(0, 0, -1)
        right = right.Magnitude > 0.001 and right.Unit or Vector3.new(1, 0, 0)

        local movement = FLIGHT_ZERO
        if keyHeld(Enum.KeyCode.W) then movement = movement + look end
        if keyHeld(Enum.KeyCode.S) then movement = movement - look end
        if keyHeld(Enum.KeyCode.D) then movement = movement + right end
        if keyHeld(Enum.KeyCode.A) then movement = movement - right end
        if keyHeld(Enum.KeyCode.Space) or keyHeld(Enum.KeyCode.E) then
            movement = movement + Vector3.new(0, 1, 0)
        end
        if keyHeld(Enum.KeyCode.LeftControl) or keyHeld(Enum.KeyCode.RightControl)
            or keyHeld(Enum.KeyCode.Q) then
            movement = movement - Vector3.new(0, 1, 0)
        end

        if movement.Magnitude > 0 then
            ManualFlight.liftUntil = nil
            ManualFlight.velocity.VectorVelocity = movement.Unit * ManualFlight.Speed
        elseif ManualFlight.liftUntil and os.clock() < ManualFlight.liftUntil then
            ManualFlight.velocity.VectorVelocity = Vector3.new(0, math.min(ManualFlight.Speed, 18), 0)
        else
            ManualFlight.velocity.VectorVelocity = FLIGHT_ZERO
        end
    end

    local function setManualFlight(enabled)
        ManualFlight.Enabled = enabled == true
        if ManualFlight.Enabled then
            Motion.release()
            local character, root, humanoid = Motion.character()
            if character then attachManualFlight(root, humanoid) end
        else
            clearManualFlight()
        end
    end

    local setFlyToggle = createCombatToggle(ConfigPage, "ManualFlyToggleCard", "Voo", 4, function(state)
        setManualFlight(state)
    end)

    local FlySpeedCard = createStyledCard(ConfigPage, "ManualFlySpeedCard", 96, 3)
    local FlySpeedTitle = Instance.new("TextLabel")
    FlySpeedTitle.Name = "ManualFlySpeedTitle"
    FlySpeedTitle.Size = UDim2.new(1, -112, 0, 24)
    FlySpeedTitle.Position = UDim2.fromOffset(16, 8)
    FlySpeedTitle.BackgroundTransparency = 1
    FlySpeedTitle.Text = "Speed Voo"
    FlySpeedTitle.TextColor3 = Theme.Text
    FlySpeedTitle.Font = Enum.Font.GothamBold
    FlySpeedTitle.TextSize = 14
    FlySpeedTitle.TextXAlignment = Enum.TextXAlignment.Left
    FlySpeedTitle.Parent = FlySpeedCard

    local FlySpeedValue = Instance.new("TextLabel")
    FlySpeedValue.Name = "ManualFlySpeedValue"
    FlySpeedValue.Size = UDim2.fromOffset(86, 24)
    FlySpeedValue.Position = UDim2.new(1, -102, 0, 8)
    FlySpeedValue.BackgroundTransparency = 1
    FlySpeedValue.Text = tostring(ManualFlight.Speed)
    FlySpeedValue.TextColor3 = Theme.Accent2
    FlySpeedValue.Font = Enum.Font.GothamBold
    FlySpeedValue.TextSize = 14
    FlySpeedValue.TextXAlignment = Enum.TextXAlignment.Right
    FlySpeedValue.Parent = FlySpeedCard

    local FlySpeedTrack = Instance.new("TextButton")
    FlySpeedTrack.Name = "ManualFlySpeedTrack"
    FlySpeedTrack.Size = UDim2.new(1, -32, 0, 8)
    FlySpeedTrack.Position = UDim2.fromOffset(16, 50)
    FlySpeedTrack.BackgroundColor3 = Theme.BgSecondary
    FlySpeedTrack.BorderSizePixel = 0
    FlySpeedTrack.Text = ""
    FlySpeedTrack.AutoButtonColor = false
    FlySpeedTrack.Parent = FlySpeedCard
    addCorner(FlySpeedTrack, 4)

    local FlySpeedFill = Instance.new("Frame")
    FlySpeedFill.Name = "ManualFlySpeedFill"
    FlySpeedFill.BackgroundColor3 = Theme.Accent2
    FlySpeedFill.BorderSizePixel = 0
    FlySpeedFill.Parent = FlySpeedTrack
    addCorner(FlySpeedFill, 4)

    local FlySpeedKnob = Instance.new("Frame")
    FlySpeedKnob.Name = "ManualFlySpeedKnob"
    FlySpeedKnob.Size = UDim2.fromOffset(18, 18)
    FlySpeedKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    FlySpeedKnob.BorderSizePixel = 0
    FlySpeedKnob.Parent = FlySpeedTrack
    addCorner(FlySpeedKnob, 9)
    addStroke(FlySpeedKnob, Theme.Accent2, 1, 0.1)

    for _, endpoint in ipairs({{text = "1", right = false}, {text = "200", right = true}}) do
        local mark = Instance.new("TextLabel")
        mark.Name = endpoint.right and "FlySpeedMax" or "FlySpeedMin"
        mark.Size = UDim2.fromOffset(56, 20)
        mark.Position = endpoint.right and UDim2.new(1, -72, 0, 68) or UDim2.fromOffset(16, 68)
        mark.BackgroundTransparency = 1
        mark.Text = endpoint.text
        mark.TextColor3 = Theme.TextDim
        mark.TextSize = 12
        mark.Font = Enum.Font.Gotham
        mark.TextXAlignment = endpoint.right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
        mark.Parent = FlySpeedCard
    end

    local function renderFlySpeed()
        local fraction = (ManualFlight.Speed - 1) / 199
        FlySpeedFill.Size = UDim2.new(fraction, 0, 1, 0)
        FlySpeedKnob.Position = UDim2.new(fraction, -9, 0.5, -9)
        FlySpeedValue.Text = tostring(ManualFlight.Speed)
    end

    local draggingFlySpeed = false
    local function setFlySpeedFromX(screenX)
        local width = FlySpeedTrack.AbsoluteSize.X
        if width <= 0 then return end
        local fraction = math.clamp((screenX - FlySpeedTrack.AbsolutePosition.X) / width, 0, 1)
        ManualFlight.Speed = math.clamp(math.floor(1 + 199 * fraction + 0.5), 1, 200)
        renderFlySpeed()
    end
    renderFlySpeed()
    connect(FlySpeedTrack.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingFlySpeed = true
            setFlySpeedFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if draggingFlySpeed and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFlySpeedFromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingFlySpeed = false
        end
    end)

    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        if not ManualFlight.Enabled or destroyed then return end
        elapsed = elapsed + dt
        if elapsed < 1 / 30 then return end
        elapsed = 0
        local ok, err = pcall(updateManualFlight)
        if not ok then
            warn("[Random Hub | Voo] " .. tostring(err))
            setFlyToggle(false)
        end
    end)
    Stoppers.ManualFlight = function()
        ManualFlight.Enabled = false
        clearManualFlight()
    end
end)

local SmallGui = Instance.new("ScreenGui")
SmallGui.Name = "FlyToggle"
SmallGui.ResetOnSpawn = false
SmallGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SmallGui.IgnoreGuiInset = true
SmallGui.DisplayOrder = 1000
SmallGui.Parent = UIParent

local FloatingBtn = Instance.new("TextButton")
FloatingBtn.Name = "FloatingBtn"
FloatingBtn.Size = UDim2.fromOffset(60, 60)
FloatingBtn.Position = UDim2.new(0, 20, 0.5, -30)
FloatingBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
FloatingBtn.BorderSizePixel = 0
FloatingBtn.Text = "🎲"
FloatingBtn.TextColor3 = Theme.Accent2
FloatingBtn.Font = Enum.Font.GothamBold
FloatingBtn.TextSize = 30
FloatingBtn.AutoButtonColor = false
FloatingBtn.Active = true
FloatingBtn.Parent = SmallGui
addCorner(FloatingBtn, 30)
addStroke(FloatingBtn, Color3.fromRGB(255, 255, 255), 2, 0.7)
addGradient(FloatingBtn, Theme.Accent1, Theme.Accent2, 45)

local function openUI()
    if destroyed or uiOpen then return end
    uiOpen = true
    ScreenGui.Enabled = true
    Main.Size = UDim2.fromOffset(0, 0)
    Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    tween(Main, {Size = CONFIG.UISize, Position = getScaledWindowOffset()}, 0.3, Enum.EasingStyle.Back)
end

local function hideUI()
    if destroyed or not uiOpen then return end
    uiOpen = false
    tween(Main, {Size = UDim2.fromOffset(0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}, 0.2)
    task.delay(0.21, function()
        if not destroyed and not uiOpen and ScreenGui then
            ScreenGui.Enabled = false
            Main.Size = CONFIG.UISize
            Main.Position = getScaledWindowOffset()
        end
    end)
end

local function destroyUI()
    if destroyed then return end
    destroyed = true
    if Motion and Motion.cancelLongTravel then Motion.cancelLongTravel() end
    TeleportLoading.finish()
    if stopAutoFarm then pcall(stopAutoFarm) end
    if stopCombat then pcall(stopCombat) end
    for _, stopper in pairs(Stoppers) do
        pcall(stopper)
    end
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    for animation in pairs(activeTweens) do
        pcall(function() animation:Cancel() end)
    end
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() SmallGui:Destroy() end)
    pcall(function() if _G.__AnimePieceHomeUIStop == destroyUI then _G.__AnimePieceHomeUIStop = nil end end)
    pcall(function() if _G.__RamdomHubStop == destroyUI then _G.__RamdomHubStop = nil end end)
end

local function toggleUI()
    if uiOpen then hideUI() else openUI() end
end

connect(FloatingBtn.MouseEnter, function()
    tween(FloatingBtn, {Size = UDim2.fromOffset(66, 66)}, 0.15)
end)
connect(FloatingBtn.MouseLeave, function()
    tween(FloatingBtn, {Size = UDim2.fromOffset(60, 60)}, 0.15)
end)

local draggingSmall = false
local smallDragStart = nil
local smallStartPosition = nil
local clickCandidate = false
local SMALL_DRAG_THRESHOLD = 5
connect(FloatingBtn.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingSmall = true
        clickCandidate = true
        smallDragStart = input.Position
        smallStartPosition = FloatingBtn.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not draggingSmall then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - smallDragStart
        if delta.Magnitude > SMALL_DRAG_THRESHOLD then clickCandidate = false end
        FloatingBtn.Position = UDim2.new(
            smallStartPosition.X.Scale, smallStartPosition.X.Offset + delta.X,
            smallStartPosition.Y.Scale, smallStartPosition.Y.Offset + delta.Y
        )
    end
end)
connect(UserInputService.InputEnded, function(input)
    if not draggingSmall then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingSmall = false
        if clickCandidate then toggleUI() end
    end
end)

if CloseBtn then
    connect(CloseBtn.MouseButton1Click, destroyUI)
end
_G.__AnimePieceHomeUIStop = destroyUI
_G.__RamdomHubStop = destroyUI

Main.Size = UDim2.fromOffset(0, 0)
task.delay(0.05, function()
    if not destroyed then
        tween(Main, {Size = CONFIG.UISize, Position = getScaledWindowOffset()}, 0.35, Enum.EasingStyle.Back)
    end
end)