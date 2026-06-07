-- ============================================
-- NEXHUB UNIVERSAL LOADER v2.0 (VELARIS UI)
-- Satu Script Untuk Semua Game
-- ============================================
local VelarisUI
do
    -- [PATCH] Fix untuk Notify.lua di repository remote yang lupa mendefinisikan HttpService
    pcall(function()
        getgenv().HttpService = game:GetService("HttpService")
    end)
    
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/nexiuse/NexHub_UI/refs/heads/main/NexHub_CustomUI.lua", true))()
    end)
    VelarisUI = ok and result or nil
end

if not VelarisUI then
    warn("Gagal merender VelarisUI.")
    return
end

-- ============================================
-- THEME
-- ============================================
pcall(function()
    VelarisUI:AddTheme({
        Name = "Nex",
        Icon = Color3.fromHex("#ffffff"),
        Accent = Color3.fromRGB(191, 0, 255),     -- ungu terang mengkilap
        Dialog = Color3.fromHex("#ffffff"),
        Outline = Color3.fromHex("#9400D3"),
        Text = Color3.fromHex("#f8fafc"),
        Placeholder = Color3.fromHex("#c084fc"),
        Button = Color3.fromHex("#9400D3"),
        WindowBackground = Color3.fromHex("#14002A") -- dark purple, bukan hitam murni
    })
end)

-- ============================================
-- KONFIGURASI GAME & API
-- ============================================
local API_URL = "https://nexhubser-api.vercel.app/api/verify"
local HttpService = game:GetService("HttpService")
local currentPlaceId = game.PlaceId
local currentGameId = game.GameId

-- Daftar game yang didukung
local GameList = {
    -- FREE GAMES
    
    -- PREMIUM GAMES (Butuh Key)
    { name = "Blox Fruits", placeIds = {2753915549, 4442272183, 7449423635}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubBf.lua" },

    { name = "Violence District", placeIds = {93978595733734}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubVD.lua" },

    { name = "Sailor Piece", placeIds = {77747658251236}, gameIds = {9186719164}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubSP.lua" },

    { name = "Bite By Night", gameIds = {8202280624}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubBBN.lua" },

    { name = "Dueling Grounds", placeIds = {94217045453265}, gameIds = {9051406594}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubDuelingGrounds" },

    { name = "Fish God", placeIds = {121500015379301}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubFishGod.lua" },

    { name = "Survive The Apocalypse", placeIds = {90148635862803}, gameIds = {9098570654}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubSTA.lua" },

    { name = "Steal A Brainrots", gameIds = {7709344486}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubSAB.lua" },

    { name = "Slime RNG", placeIds = {92416421522960}, gameIds = {9792947201}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubSlimeRNG.lua" },

    { name = "Kick A Lucky Block", placeIds = {89469502395769}, gameIds = {10004244222}, type = "premium", scriptUrl = "https://raw.githubusercontent.com/nexiuse/NexHubMain/refs/heads/main/NexHubKaLB.lua" },
}

-- ============================================
-- DETEKSI GAME OTOMATIS
-- ============================================
local detectedGame = nil

for _, gameInfo in ipairs(GameList) do
    if gameInfo.placeIds then
        for _, pid in ipairs(gameInfo.placeIds) do
            if currentPlaceId == pid then detectedGame = gameInfo break end
        end
    end
    if not detectedGame and gameInfo.gameIds then
        for _, gid in ipairs(gameInfo.gameIds) do
            if currentGameId == gid then detectedGame = gameInfo break end
        end
    end
    if detectedGame then break end
end

-- ============================================
-- GAME TIDAK DIKENALI
-- ============================================
if not detectedGame then
    VelarisUI:MakeNotify({
        Title = "NexHub Loader",
        Content = "Game tidak dikenali.\nPlaceId: " .. tostring(currentPlaceId) .. "\nGameId: " .. tostring(currentGameId),
        Delay = 10,
        Icon = "rbxassetid://7733765398"
    })
    return
end

-- ============================================
-- FUNGSI: MUAT SCRIPT GAME
-- ============================================
local function loadGameScript()
    task.wait(0.5)
    
    -- Destroy loader window dan semua sisa GUI sebelum memuat Game Script
    pcall(function()
        local containers = {}
        pcall(function() table.insert(containers, gethui and gethui() or game:GetService("CoreGui")) end)
        pcall(function() table.insert(containers, game:GetService("CoreGui")) end)
        for _, parent in ipairs(containers) do
            if parent then
                for _, gui in ipairs(parent:GetChildren()) do
                    if gui:IsA("ScreenGui") then
                        local name = gui.Name or ""
                        if name == "NexHub" or name == "ToggleUIButton" or name == "VelarisUI" or name == "VelarisNotifyGui" then
                            -- PENTING: Hanya sembunyikan (Enabled = false) daripada di-Destroy().
                            -- Menghancurkan GUI secara paksa (Destroy) sering membuat koneksi RenderStepped 
                            -- bawaan UI library mengalami memory leak/crash (C stack overflow) di background.
                            pcall(function() 
                                gui.Enabled = false 
                                gui.Name = "NexHub_Old_Hidden"
                            end)
                        end
                    end
                end
            end
        end
    end)
    
    task.wait(1.5) -- Beri waktu lebih agar executor bisa membersihkan memori GUI yang lama
    
    local scriptSource
    local successHttp, errHttp = pcall(function()
        scriptSource = game:HttpGet(detectedGame.scriptUrl)
    end)

    if not successHttp then
        local errMsg = tostring(errHttp)
        if errMsg:find("404") then
            errMsg = "File tidak ditemukan di GitHub! Cek URL: " .. detectedGame.scriptUrl
        end
        warn("NexHub Loader Error (HTTP): " .. errMsg)
        return
    end

    local loadedScript, loadErr = loadstring(scriptSource)
    if loadedScript then
        -- Gunakan task.defer agar eksekusi script ini dijadwalkan secara aman 
        -- di siklus memori (thread) yang benar-benar baru dan terpisah.
        task.defer(loadedScript)
    else
        warn("NexHub Loader Error (Compile): " .. tostring(loadErr))
    end
end

-- ============================================
-- JALUR FREE: LANGSUNG MUAT
-- ============================================
if detectedGame.type == "free" then
    VelarisUI:MakeNotify({
        Title = "NexHub - Free Access",
        Content = "Game: " .. detectedGame.name .. " (Gratis). Memuat otomatis...",
        Delay = 3,
        Icon = "rbxassetid://7733765398"
    })
    task.wait(1)
    loadGameScript()
    return
end
-- =============================================
-- PREMIUM: CUSTOM AUTH UI  (animated, English)
-- =============================================
local TweenService = game:GetService("TweenService")

local Analytics = game:GetService("RbxAnalyticsService")
local HWID = "Unknown"
pcall(function()
    if gethwid then HWID = gethwid() else HWID = Analytics:GetClientId() end
end)

-- ── Auto-Login: cek key tersimpan ──────────────────────────────
local KEY_FILE = "nexhub_key.txt"
local savedKey = nil

if isfile and isfile(KEY_FILE) then
    local raw = readfile(KEY_FILE)
    if raw and raw ~= "" then savedKey = raw end
end

if savedKey then
    VelarisUI:MakeNotify({
        Title = "NexHub",
        Content = "Verifying saved key...",
        Delay = 3,
        Icon = "rbxassetid://7733765398"
    })

    local autoOk, autoResp = pcall(function()
        local httpReq = (syn and syn.request) or request
            or http_request or (fluxus and fluxus.request)
        if not httpReq then error("HTTP not supported") end
        local res = httpReq({
            Url     = API_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = HttpService:JSONEncode({
                key      = savedKey,
                hwid     = HWID,
                userid   = tostring(game:GetService("Players").LocalPlayer.UserId),
                username = game:GetService("Players").LocalPlayer.Name,
            }),
        })
        return HttpService:JSONDecode(res.Body)
    end)

    if autoOk and autoResp and autoResp.success then
        -- Key masih valid, langsung load tanpa tampilkan UI
        VelarisUI:MakeNotify({
            Title = "NexHub",
            Content = "Welcome back! Loading " .. detectedGame.name .. "...",
            Delay = 3,
            Icon = "rbxassetid://7733085271"
        })
        task.wait(0.5)
        loadGameScript()
        return
    else
        -- Key sudah tidak valid (expired/reset), hapus file dan lanjut ke UI input
        pcall(function() if delfile then delfile(KEY_FILE) end end)
        VelarisUI:MakeNotify({
            Title = "NexHub",
            Content = "Your session has expired. Please re-enter your key.",
            Delay = 4,
            Icon = "rbxassetid://7733765398"
        })
        task.wait(1)
    end
end

-- ── Screen GUI ────────────────────────────────────────────────”€
local authGui = Instance.new("ScreenGui")
authGui.Name           = "NexHubAuth"
authGui.ResetOnSpawn   = false
authGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() authGui.Parent = gethui() end)
if not authGui.Parent then authGui.Parent = game:GetService("CoreGui") end

-- Dark overlay (fades in)
local overlay = Instance.new("Frame", authGui)
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.fromRGB(5, 0, 12)
overlay.BackgroundTransparency = 1       -- starts invisible
overlay.BorderSizePixel        = 0
overlay.ZIndex                 = 10

TweenService:Create(overlay, TweenInfo.new(0.35), {
    BackgroundTransparency = 0.4
}):Play()

-- â”€â”€ Auth Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local CW, CH = 390, 285       -- card width x height (edit here)

local card = Instance.new("Frame", authGui)
card.Name                   = "AuthCard"
card.AnchorPoint            = Vector2.new(0.5, 0.5)
card.Position               = UDim2.fromScale(0.5, 0.5)
card.Size                   = UDim2.fromOffset(CW * 0.82, CH * 0.82)  -- start small
card.BackgroundColor3       = Color3.fromRGB(11, 0, 22)
card.BackgroundTransparency = 1           -- starts invisible
card.BorderSizePixel        = 0
card.ClipsDescendants       = true        -- needed for shimmer clip
card.ZIndex                 = 11

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

-- Purple border
local stroke = Instance.new("UIStroke", card)
stroke.Color        = Color3.fromRGB(191, 0, 255)
stroke.Thickness    = 1.5
stroke.Transparency = 0.2

-- Background gradient
local bgGrad = Instance.new("UIGradient", card)
bgGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(26,  0,  52)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(11,  0,  22)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(18,  0,  38)),
})
bgGrad.Rotation = 135

-- Card entrance: scale up + fade in
TweenService:Create(card,
    TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size                   = UDim2.fromOffset(CW, CH),
    BackgroundTransparency = 0.06,
}):Play()

-- â”€â”€ Shimmer sweep (periodic, diagonal) â”€â”€â”€â”€â”€â”€â”€
local shimmer = Instance.new("Frame", card)
shimmer.Name             = "Shimmer"
shimmer.Size             = UDim2.new(0.38, 0, 1, 0)
shimmer.Position         = UDim2.new(-0.45, 0, 0, 0)
shimmer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shimmer.BorderSizePixel  = 0
shimmer.ZIndex           = 20
shimmer.Rotation         = 12

local shimGrad = Instance.new("UIGradient", shimmer)
shimGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0,    1),
    NumberSequenceKeypoint.new(0.45, 0.88),
    NumberSequenceKeypoint.new(0.55, 0.88),
    NumberSequenceKeypoint.new(1,    1),
})

task.spawn(function()
    task.wait(0.6)
    while authGui.Parent do
        local t = TweenService:Create(shimmer,
            TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            Position = UDim2.new(1.45, 0, 0, 0)
        })
        t:Play()
        t.Completed:Wait()
        shimmer.Position = UDim2.new(-0.45, 0, 0, 0)
        task.wait(4)
    end
end)

-- â”€â”€ Top highlight bar (static glossy line) â”€â”€â”€
local gloss = Instance.new("Frame", card)
gloss.Size                   = UDim2.new(1, 0, 0, 2)
gloss.BackgroundColor3       = Color3.fromRGB(210, 130, 255)
gloss.BackgroundTransparency = 0.5
gloss.BorderSizePixel        = 0
gloss.ZIndex                 = 19
Instance.new("UICorner", gloss).CornerRadius = UDim.new(0, 14)

-- â”€â”€ Helper: text label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function mkLabel(parent, text, font, size, color, px, py, sw, sh, xAlign)
    local lb = Instance.new("TextLabel", parent)
    lb.BackgroundTransparency = 1
    lb.Text           = text
    lb.Font           = font or Enum.Font.Gotham
    lb.TextSize       = size  or 12
    lb.TextColor3     = color or Color3.fromRGB(255,255,255)
    lb.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    lb.Position       = UDim2.new(0, px, 0, py)
    lb.Size           = UDim2.new(1, sw or -24, 0, sh or 18)
    lb.ZIndex         = 12
    return lb
end

-- Title & subtitle
mkLabel(card, "NexHub  |  Authentication",
    Enum.Font.GothamBold, 14, Color3.fromRGB(218, 178, 255), 14, 10, -28, 22)
mkLabel(card, "Game: "..detectedGame.name.."   |   Premium Access",
    Enum.Font.Gotham, 10, Color3.fromRGB(148, 88, 200), 14, 34, -28, 15)

-- Divider
local div = Instance.new("Frame", card)
div.Size                   = UDim2.new(1, -28, 0, 1)
div.Position               = UDim2.new(0, 14, 0, 56)
div.BackgroundColor3       = Color3.fromRGB(191, 0, 255)
div.BackgroundTransparency = 0.6
div.BorderSizePixel        = 0
div.ZIndex                 = 12

-- —————————————————————————————
local inputBox = Instance.new("TextBox", card)
inputBox.Size                   = UDim2.new(1, -28, 0, 34)
inputBox.Position               = UDim2.new(0, 14, 0, 65)
inputBox.BackgroundColor3       = Color3.fromRGB(24, 0, 46)
inputBox.BackgroundTransparency = 0.18
inputBox.BorderSizePixel        = 0
inputBox.PlaceholderText        = "Enter your license key..."
inputBox.PlaceholderColor3      = Color3.fromRGB(105, 72, 125)
inputBox.Text                   = ""
inputBox.TextColor3             = Color3.fromRGB(240, 220, 255)
inputBox.Font                   = Enum.Font.Gotham
inputBox.TextSize               = 12
inputBox.ClearTextOnFocus       = false
inputBox.ZIndex                 = 12
Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 8)
local iStroke = Instance.new("UIStroke", inputBox)
iStroke.Color = Color3.fromRGB(191, 0, 255); iStroke.Transparency = 0.55

-- Input focus glow
inputBox.Focused:Connect(function()
    TweenService:Create(iStroke, TweenInfo.new(0.2), {Transparency = 0.1}):Play()
end)
inputBox.FocusLost:Connect(function()
    TweenService:Create(iStroke, TweenInfo.new(0.2), {Transparency = 0.55}):Play()
end)

-- â”€â”€ Status label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local statusLbl = mkLabel(card, "",
    Enum.Font.Gotham, 10, Color3.fromRGB(255, 100, 100), 14, 103, -28, 13)
statusLbl.BackgroundTransparency = 1
statusLbl.TextTransparency       = 1   -- hidden initially

local function showStatus(text, color)
    statusLbl.Text          = text
    statusLbl.TextColor3    = color
    statusLbl.TextTransparency = 1
    TweenService:Create(statusLbl, TweenInfo.new(0.2), {TextTransparency = 0}):Play()
end

-- â”€â”€ Redeem button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local redeemBtn = Instance.new("TextButton", card)
redeemBtn.Size             = UDim2.new(1, -28, 0, 34)
redeemBtn.Position         = UDim2.new(0, 14, 0, 120)
redeemBtn.BackgroundColor3 = Color3.fromRGB(148, 0, 211)
redeemBtn.BorderSizePixel  = 0
redeemBtn.Text             = "Redeem Key"
redeemBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
redeemBtn.Font             = Enum.Font.GothamBold
redeemBtn.TextSize         = 13
redeemBtn.ZIndex           = 12
Instance.new("UICorner", redeemBtn).CornerRadius = UDim.new(0, 8)

-- Button gradient (shiny)
local rGrad = Instance.new("UIGradient", redeemBtn)
rGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(212, 52, 255)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(108, 0, 188)),
})
rGrad.Rotation = 90

-- Button shimmer
local btnShimmer = Instance.new("Frame", redeemBtn)
btnShimmer.Size             = UDim2.new(0.35, 0, 1, 0)
btnShimmer.Position         = UDim2.new(-0.4, 0, 0, 0)
btnShimmer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
btnShimmer.BorderSizePixel  = 0
btnShimmer.ZIndex           = 13
local bsGrad = Instance.new("UIGradient", btnShimmer)
bsGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1)
})
task.spawn(function()
    task.wait(1.2)
    while authGui.Parent do
        local t = TweenService:Create(btnShimmer, TweenInfo.new(0.7, Enum.EasingStyle.Sine), {
            Position = UDim2.new(1.4, 0, 0, 0)
        })
        t:Play(); t.Completed:Wait()
        btnShimmer.Position = UDim2.new(-0.4, 0, 0, 0)
        task.wait(4.5)
    end
end)

-- Hover & press animations
redeemBtn.MouseEnter:Connect(function()
    TweenService:Create(redeemBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(175, 20, 245)
    }):Play()
end)
redeemBtn.MouseLeave:Connect(function()
    TweenService:Create(redeemBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(148, 0, 211)
    }):Play()
end)
redeemBtn.MouseButton1Down:Connect(function()
    TweenService:Create(redeemBtn, TweenInfo.new(0.08), {
        Size = UDim2.new(1, -32, 0, 32)
    }):Play()
end)
redeemBtn.MouseButton1Up:Connect(function()
    TweenService:Create(redeemBtn, TweenInfo.new(0.12, Enum.EasingStyle.Back), {
        Size = UDim2.new(1, -28, 0, 34)
    }):Play()
end)

-- ── Get Key buttons (3 platform) ───────────────────────
local div2 = Instance.new("Frame", card)
div2.Size                   = UDim2.new(1, -28, 0, 1)
div2.Position               = UDim2.new(0, 14, 0, 162)
div2.BackgroundColor3       = Color3.fromRGB(191, 0, 255)
div2.BackgroundTransparency = 0.7
div2.BorderSizePixel        = 0
div2.ZIndex                 = 12

mkLabel(card, "Get a free 24-hour key",
    Enum.Font.Gotham, 9, Color3.fromRGB(148, 88, 200), 14, 168, -28, 13)

local BTN_W, BTN_H, BTN_Y = 114, 32, 184

local function makePlatformBtn(label, subLabel, bgTop, bgBot, xPos)
    local frame = Instance.new("Frame", card)
    frame.Size             = UDim2.fromOffset(BTN_W, BTN_H)
    frame.Position         = UDim2.new(0, xPos, 0, BTN_Y)
    frame.BackgroundColor3 = bgTop
    frame.BorderSizePixel  = 0
    frame.ZIndex           = 12
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local grad = Instance.new("UIGradient", frame)
    grad.Color    = ColorSequence.new(bgTop, bgBot)
    grad.Rotation = 90

    local dot = Instance.new("Frame", frame)
    dot.Size             = UDim2.fromOffset(6, 6)
    dot.Position         = UDim2.new(0, 8, 0.5, -3)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BackgroundTransparency = 0.3
    dot.BorderSizePixel  = 0
    dot.ZIndex           = 13
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local nameLbl = Instance.new("TextLabel", frame)
    nameLbl.Size              = UDim2.new(1, -20, 0, 16)
    nameLbl.Position          = UDim2.new(0, 18, 0, 4)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text              = label
    nameLbl.TextColor3        = Color3.fromRGB(255, 255, 255)
    nameLbl.Font              = Enum.Font.GothamBold
    nameLbl.TextSize          = 10
    nameLbl.TextXAlignment    = Enum.TextXAlignment.Left
    nameLbl.ZIndex            = 13

    local subLbl = Instance.new("TextLabel", frame)
    subLbl.Size               = UDim2.new(1, -20, 0, 12)
    subLbl.Position           = UDim2.new(0, 18, 0, 17)
    subLbl.BackgroundTransparency = 1
    subLbl.Text               = subLabel
    subLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    subLbl.TextTransparency   = 0.35
    subLbl.Font               = Enum.Font.Gotham
    subLbl.TextSize           = 8
    subLbl.TextXAlignment     = Enum.TextXAlignment.Left
    subLbl.ZIndex             = 13

    local hitbox = Instance.new("TextButton", frame)
    hitbox.Size               = UDim2.fromScale(1, 1)
    hitbox.BackgroundTransparency = 1
    hitbox.Text               = ""
    hitbox.ZIndex             = 14

    hitbox.MouseEnter:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency = 0.25}):Play()
    end)
    hitbox.MouseLeave:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
    end)
    hitbox.MouseButton1Down:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.08), {Size = UDim2.fromOffset(BTN_W - 4, BTN_H - 3)}):Play()
    end)
    hitbox.MouseButton1Up:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Size = UDim2.fromOffset(BTN_W, BTN_H)}):Play()
    end)

    return hitbox
end

local lootBtn = makePlatformBtn("LootLabs", "Click to copy", Color3.fromRGB(0, 168, 107), Color3.fromRGB(0, 110, 70), 14)
local workBtn = makePlatformBtn("Workink", "Click to copy", Color3.fromRGB(33, 133, 243), Color3.fromRGB(15, 90, 190), 14 + BTN_W + 6)
local linvBtn = makePlatformBtn("Linkvertise", "Click to copy", Color3.fromRGB(230, 80, 30), Color3.fromRGB(180, 45, 10), 14 + (BTN_W + 6) * 2)

-- HWID footer
mkLabel(card, "HWID  "..HWID:sub(1, 20).."...",
    Enum.Font.Gotham, 9, Color3.fromRGB(100, 60, 140), 14, 226, -28, 14)

-- â”€â”€ Button logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local keyValid     = false
local isValidating = false

redeemBtn.MouseButton1Click:Connect(function()
    if isValidating then return end
    local key = inputBox.Text:match("^%s*(.-)%s*$")
    if key == "" then
        showStatus("Please enter your key first.", Color3.fromRGB(255, 200, 50))
        return
    end
    isValidating   = true
    redeemBtn.Text = "Verifying..."
    showStatus("Contacting verification server...", Color3.fromRGB(175, 145, 255))

    task.spawn(function()
        local ok, resp = pcall(function()
            local httpReq = (syn and syn.request) or request
                or http_request or (fluxus and fluxus.request)
            if not httpReq then error("HTTP requests not supported by this executor") end
            local res = httpReq({
                Url     = API_URL,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = HttpService:JSONEncode({
                    key      = key,
                    hwid     = HWID,
                    userid   = tostring(game:GetService("Players").LocalPlayer.UserId),
                    username = game:GetService("Players").LocalPlayer.Name,
                }),
            })
            return HttpService:JSONDecode(res.Body)
        end)

        if ok and resp and resp.success then
            showStatus("Key accepted. Loading "..detectedGame.name.."...", Color3.fromRGB(100, 255, 150))
            redeemBtn.Text = "Verified!"
            -- Border turns green
            TweenService:Create(stroke, TweenInfo.new(0.3), {
                Color = Color3.fromRGB(80, 255, 140), Transparency = 0,
            }):Play()
            task.wait(1.5)
            -- Exit animation: shrink + fade
            TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Size                   = UDim2.fromOffset(CW * 0.82, CH * 0.82),
                BackgroundTransparency = 1,
            }):Play()
            TweenService:Create(overlay, TweenInfo.new(0.35), {BackgroundTransparency = 1}):Play()
            task.wait(0.4)
            -- Simpan key ke file lokal agar tidak perlu input lagi
            pcall(function()
                if writefile then writefile(KEY_FILE, key) end
            end)
            keyValid = true
        else
            local msg = "Invalid or unregistered key."
            if ok and resp then msg = tostring(resp.message or resp.error or msg) end
            showStatus(msg:sub(1, 58), Color3.fromRGB(255, 95, 95))
            redeemBtn.Text = "Redeem Key"
            isValidating   = false
        end
    end)
end)

lootBtn.MouseButton1Click:Connect(function()
    local url = "https://nexhubser-api.vercel.app/api/start-key?hwid=" .. HWID
    pcall(function() if setclipboard then setclipboard(url) end end)
    VelarisUI:MakeNotify({
        Title = "LootLabs",
        Content = "Link copied! Open it in your browser to get a key.",
        Delay = 4, Icon = "rbxassetid://7733765398",
    })
end)

workBtn.MouseButton1Click:Connect(function()
    local url = "https://nexhubser-api.vercel.app/api/start-key-workink?hwid=" .. HWID
    pcall(function() if setclipboard then setclipboard(url) end end)
    VelarisUI:MakeNotify({
        Title = "Workink",
        Content = "Link copied! Open it in your browser to get a key.",
        Delay = 4, Icon = "rbxassetid://7733765398",
    })
end)

linvBtn.MouseButton1Click:Connect(function()
    local url = "https://nexhubser-api.vercel.app/api/start-key-linkvertise?hwid=" .. HWID
    pcall(function() if setclipboard then setclipboard(url) end end)
    VelarisUI:MakeNotify({
        Title = "Linkvertise",
        Content = "Link copied! Open it in your browser to get a key.",
        Delay = 4, Icon = "rbxassetid://7733765398",
    })
end)

-- â”€â”€ Wait & load â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
repeat task.wait(0.25) until keyValid

pcall(function() authGui:Destroy() end)
VelarisUI:MakeNotify({
    Title = "NexHub", Content = "Loading "..detectedGame.name.."...",
    Delay = 3, Icon = "rbxassetid://7733085271",
})
task.wait(0.5)
loadGameScript()
