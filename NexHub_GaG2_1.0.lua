if not game or not game:GetService("Players") then
 error("[NexHub] Must run inside Roblox game")
end

---------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------

local VERSION = "1.0"

local Config = {
 Features = {
 AutoHarvest = false, AutoSell = false, AutoWater = false,
 AutoPlant = false, RestockSniper = false, MutationTracker = false,
 WeatherBot = false, StealBot = false, InventoryOptimizer = false,
 AutoBuyPet = false, AntiAfk = true,
 },
 Timings = {
 HarvestInterval = 0.5, SellInterval = 5, WaterInterval = 3,
 PlantInterval = 5, RestockPollInterval = 1, MutationScanInterval = 3,
 WeatherPollInterval = 5, StealInterval = 1.5, InventoryCheckInterval = 10,
 PetHatchInterval = 2,
 },
 Restock = {
 TargetSeeds = {},
 BlacklistedSeeds = {},
 },
 Steal = { MinFruitValue = 100, MaxAttemptsPerNight = 20, PreferMutations = true },
 Sell = { Mode = "all", UseDailyDeal = false },
 Plant = { OnlyEmptyPlots = true, PreferSeed = nil, GridSpacing = 3 },
 Water = { WaterAll = false },
 Inventory = { FavoriteThreshold = 500, AutoPromote = true, DropThreshold = 5 },
 Pet = { MinRarity = "Rare", AutoSellUnwanted = false },
 Gear = { TargetGears = {} },
 Mutation = {
 AlertMutations = { "Rainbow", "Starstruck", "Gold", "Frozen", "Electric", "Bloodlit", "Chained" },
 PriceMultipliers = { Gold = 20, Rainbow = 50, Electric = 12, Frozen = 10, Bloodlit = 5, Chained = 8, Starstruck = 100 },
 LogToConsole = true,
 },
 UI = { Title = "NexHub", Subtitle = "Grow A Garden Automation", NotifyDuration = 5 },
}

function Config.Notify(title, text, duration)
 pcall(function()
 if _G.GAGHubWindow then
 _G.GAGHubWindow:Notify({
 Title = title or "NexHub",
 Content = text or "",
 Duration = duration or Config.UI.NotifyDuration,
 Icon = "lucide:bell"
 })
 else
 game:GetService("StarterGui"):SetCore("SendNotification", {
 Title = title or "NexHub", Text = text or "",
 Duration = duration or Config.UI.NotifyDuration,
 })
 end
 end)
end

---------------------------------------------------------------
-- CORE: NETWORKING (inlined from core/networking.lua)
---------------------------------------------------------------

local Networking = {}
local RS = game:GetService("ReplicatedStorage")

-- Internal cache
Networking._module = nil
Networking._cache = {}
Networking._connections = {}
Networking._log = true

---------------------------------------------------------------
-- RESOLVE NETWORKING MODULE
---------------------------------------------------------------

function Networking._resolve()
 if Networking._module then return Networking._module end

 -- Method 1: try require()
 local ok, result = pcall(function()
 local shared = RS:WaitForChild("SharedModules", 10)
 if not shared then error("SharedModules not found") end
 local net = shared:WaitForChild("Networking", 10)
 if not net then error("Networking not found") end
 return require(net)
 end)

 if ok and result and type(result) == "table" then
 Networking._module = result
 return result
 end

 -- Method 2: getgc — find already-loaded Networking table by checking for known keys
 local gcOk, gcResult = pcall(function()
 if not getgc then return nil end
 for _, v in pairs(getgc(true)) do
 if type(v) == "table" then
 -- Check for unique Networking structure: has Plant.PlantSeed AND Garden.CollectFruit AND SeedShop.PurchaseSeed
 local hasPlant = type(v.Plant) == "table" and type(v.Plant.PlantSeed) ~= "nil"
 local hasGarden = type(v.Garden) == "table" and type(v.Garden.CollectFruit) ~= "nil"
 local hasSeedShop = type(v.SeedShop) == "table" and type(v.SeedShop.PurchaseSeed) ~= "nil"
 if hasPlant and hasGarden and hasSeedShop then
 return v
 end
 end
 end
 return nil
 end)

 if gcOk and gcResult and type(gcResult) == "table" then
 print("[NexHub] Networking resolved via getgc")
 Networking._module = gcResult
 return gcResult
 end

 -- Method 3: try require Packet directly, then build minimal net
 local pktOk, pktResult = pcall(function()
 local shared = RS:WaitForChild("SharedModules", 10)
 if not shared then error("SharedModules not found") end
 local pkt = shared:WaitForChild("Packet", 5)
 local net = shared:WaitForChild("Networking", 5)
 if not pkt or not net then return nil end
 -- Pre-require Packet so it's in module cache, then require Networking
 require(pkt)
 return require(net)
 end)

 if pktOk and pktResult and type(pktResult) == "table" then
 print("[NexHub] Networking resolved via Packet pre-require")
 Networking._module = pktResult
 return pktResult
 end

 warn("[NexHub] Failed to resolve Networking module (all methods failed):", result or gcResult or pktResult)
 return nil
end

---------------------------------------------------------------
-- RESOLVE REMOTE BY DOT PATH
-- e.g., "Garden.CollectFruit" → Networking.Garden.CollectFruit
---------------------------------------------------------------

function Networking._resolveRemote(path)
 -- Check cache
 if Networking._cache[path] then return Networking._cache[path] end

 local net = Networking._resolve()
 if not net then return nil end

 local current = net
 for segment in string.gmatch(path, "[^%.]+") do
 if type(current) ~= "table" then
 warn("[NexHub] Remote path broken at segment:", segment, "in", path)
 return nil
 end
 current = current[segment]
 if current == nil then
 -- Try searching by iterating keys (case-insensitive fallback)
 for k, v in pairs(current or {}) do
 if string.lower(k) == string.lower(segment) then
 current = v
 break
 end
 end
 if current == nil then
 warn("[NexHub] Remote not found:", segment, "in path", path)
 return nil
 end
 end
 end

 Networking._cache[path] = current
 return current
end

---------------------------------------------------------------
-- FIRE (RemoteEvent → server)
---------------------------------------------------------------

function Networking.fire(path, ...)
 local remote = Networking._resolveRemote(path)
 if not remote then
 warn("[NexHub] Cannot fire - remote not found:", path)
 return false
 end

 local args = {...}
 local argc = select("#", ...)
 local ok, err = pcall(function()
 if remote.Fire then
 remote:Fire(unpack(args, 1, argc))
 elseif type(remote) == "table" and remote.fire then
 remote:fire(unpack(args, 1, argc))
 else
 error("Remote has no :Fire method - type: " .. typeof(remote))
 end
 end)

 if not ok then
 warn("[NexHub] Fire error on", path, ":", err)
 return false
 end

 if Networking._log then
 print("[NexHub] Fired:", path)
 end
 return true
end

---------------------------------------------------------------
-- INVOKE (RemoteFunction → server → response)
---------------------------------------------------------------

function Networking.invoke(path, ...)
 local remote = Networking._resolveRemote(path)
 if not remote then
 warn("[NexHub] Cannot invoke - remote not found:", path)
 return nil
 end

 local args = {...}
 local argc = select("#", ...)
 local ok, result = pcall(function()
 if remote.Invoke then
 return remote:Invoke(unpack(args, 1, argc))
 else
 error("Remote has no :Invoke method")
 end
 end)

 if not ok then
 warn("[NexHub] Invoke error on", path, ":", result)
 return nil
 end

 return result
end

---------------------------------------------------------------
-- LISTEN (RemoteEvent ← server)
---------------------------------------------------------------

function Networking.on(path, callback)
 local remote = Networking._resolveRemote(path)
 if not remote then
 warn("[NexHub] Cannot listen - remote not found:", path)
 return nil
 end

 local ok, connection = pcall(function()
 if remote.OnClientEvent then
 return remote.OnClientEvent:Connect(callback)
 elseif remote.Connect then
 return remote:Connect(callback)
 else
 -- Try the .Changed pattern or direct connect
 warn("[NexHub] Remote has no OnClientEvent:", path)
 return nil
 end
 end)

 if ok and connection then
 table.insert(Networking._connections, connection)
 return connection
 end
 return nil
end

---------------------------------------------------------------
-- BATCH LISTEN (connect multiple events at once)
---------------------------------------------------------------

function Networking.onMany(map)
 local connections = {}
 for path, callback in pairs(map) do
 local conn = Networking.on(path, callback)
 if conn then
 connections[path] = conn
 end
 end
 return connections
end

---------------------------------------------------------------
-- GET RAW REMOTE (for advanced usage)
---------------------------------------------------------------

function Networking.get(path)
 return Networking._resolveRemote(path)
end

---------------------------------------------------------------
-- CHECK IF REMOTE EXISTS
---------------------------------------------------------------

function Networking.exists(path)
 return Networking._resolveRemote(path) ~= nil
end

---------------------------------------------------------------
-- LOGGING
---------------------------------------------------------------

function Networking.setLogging(enabled)
 Networking._log = enabled
end

---------------------------------------------------------------
-- DISCONNECT ALL
---------------------------------------------------------------

function Networking.disconnectAll()
 for _, conn in ipairs(Networking._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Networking._connections = {}
end

---------------------------------------------------------------
-- CACHE REFRESH (call after game update)
---------------------------------------------------------------

function Networking.refreshCache()
 Networking._module = nil
 Networking._cache = {}
 Networking._resolve()
end

---------------------------------------------------------------
-- AUTO-INIT
---------------------------------------------------------------

Networking._resolve()


---------------------------------------------------------------
-- CORE: UTILITIES (inlined from core/utils.lua)
---------------------------------------------------------------

local Utils = {}
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

---------------------------------------------------------------
-- INSTANCE RESOLVER
---------------------------------------------------------------

-- Resolve dot-path: "A.B.C" → A.B.C
function Utils.resolve(root, path)
 if not root or not path then return nil end
 local current = root
 for segment in string.gmatch(path, "[^%.]+") do
 current = current:FindFirstChild(segment)
 if not current then return nil end
 end
 return current
end

-- Safe resolve with WaitForChild (timeout)
function Utils.resolveWait(root, path, timeout)
 if not root or not path then return nil end
 local current = root
 for segment in string.gmatch(path, "[^%.]+") do
 current = current:WaitForChild(segment, timeout or 10)
 if not current then return nil end
 end
 return current
end

---------------------------------------------------------------
-- PLAYER HELPERS
---------------------------------------------------------------

function Utils.getLocalPlayer()
 return Players.LocalPlayer
end

function Utils.getCharacter()
 local lp = Players.LocalPlayer
 return lp and lp.Character or nil
end

function Utils.getHumanoidRootPart()
 local char = Utils.getCharacter()
 return char and char:FindFirstChild("HumanoidRootPart")
end

function Utils.getHumanoid()
 local char = Utils.getCharacter()
 return char and char:FindFirstChildWhichIsA("Humanoid")
end

function Utils.getPlotId()
 local lp = Players.LocalPlayer
 return lp and lp:GetAttribute("PlotId")
end

function Utils.getMyGarden()
 local plotId = Utils.getPlotId()
 if not plotId then return nil end
 local gardens = workspace:FindFirstChild("Gardens")
 if not gardens then return nil end
 return gardens:FindFirstChild("Plot" .. tostring(plotId))
end

---------------------------------------------------------------
-- GARDEN HELPERS
---------------------------------------------------------------

-- Get all plants in a garden plot
function Utils.getPlantsInGarden(garden)
 if not garden then return {} end
 local plants = {}
 for _, child in ipairs(garden:GetDescendants()) do
 if child:IsA("Model") and child:GetAttribute("SeedName") then
 table.insert(plants, child)
 end
 end
 return plants
end

-- Get plant info from attributes
function Utils.getPlantInfo(plant)
 if not plant then return nil end
 return {
 Name = plant:GetAttribute("SeedName") or plant.Name,
 Growth = plant:GetAttribute("Growth") or 0,
 Mutation = plant:GetAttribute("Mutation"),
 Age = plant:GetAttribute("Age") or 0,
 Size = plant:GetAttribute("Size") or 1,
 IsRipe = (plant:GetAttribute("Growth") or 0) >= 1,
 Owner = plant:GetAttribute("Owner"),
 Instance = plant,
 }
end

-- Get all fruits in a garden
function Utils.getFruitsInGarden(garden)
 if not garden then return {} end
 local fruits = {}
 for _, child in ipairs(garden:GetDescendants()) do
 if child:GetAttribute("FruitName") or child:GetAttribute("IsFruit") then
 table.insert(fruits, child)
 end
 end
 return fruits
end

-- Get all gardens in workspace
function Utils.getAllGardens()
 local gardens = workspace:FindFirstChild("Gardens")
 if not gardens then return {} end
 local result = {}
 for _, garden in ipairs(gardens:GetChildren()) do
 table.insert(result, garden)
 end
 return result
end

---------------------------------------------------------------
-- VALUE CALCULATOR
---------------------------------------------------------------

-- Calculate fruit sell value (mirrors FruitValueCalc)
-- baseValue * size^exponent * mutationMult * sizeMult
function Utils.calculateFruitValue(seedName, size, mutation, sellData, mutationData)
 local base = sellData and sellData[seedName] or 0
 local sizeExponent = 2.65
 local sizeMult = 1
 local mutationMult = 1

 if mutation and mutationData then
 local mData = mutationData[mutation]
 mutationMult = mData and mData.PriceMultiplier or 1
 end

 local value = base * (size ^ sizeExponent) * sizeMult * mutationMult
 return math.floor(value)
end

---------------------------------------------------------------
-- INVENTORY HELPERS
---------------------------------------------------------------

-- Get backpack contents
function Utils.getBackpackItems()
 local lp = Players.LocalPlayer
 local bp = lp and lp:FindFirstChild("Backpack")
 if not bp then return {} end
 local items = {}
 for _, tool in ipairs(bp:GetChildren()) do
 if tool:IsA("Tool") then
 table.insert(items, {
 Name = tool.Name,
 Instance = tool,
 Type = tool:GetAttribute("ItemType") or "Unknown",
 })
 end
 end
 return items
end

-- Get equipped tool
function Utils.getEquippedTool()
 local char = Utils.getCharacter()
 if not char then return nil end
 for _, child in ipairs(char:GetChildren()) do
 if child:IsA("Tool") then
 return child
 end
 end
 return nil
end

---------------------------------------------------------------
-- NIGHT CHECK
---------------------------------------------------------------

function Utils.isNight()
 local night = RS:FindFirstChild("Night")
 if night then return night.Value == true end
 -- Fallback: check lighting
 local clock = game:GetService("Lighting").ClockTime
 return clock >= 18 or clock < 6
end

---------------------------------------------------------------
-- SHECKLE BALANCE
---------------------------------------------------------------

function Utils.getSheckles()
 local lp = Players.LocalPlayer
 local leaderstats = lp and lp:FindFirstChild("leaderstats")
 if not leaderstats then return 0 end
 local sheckles = leaderstats:FindFirstChild("Sheckles")
 return sheckles and sheckles.Value or 0
end

---------------------------------------------------------------
-- SAFE CALL
---------------------------------------------------------------

function Utils.safeCall(fn, ...)
 local ok, result = pcall(fn, ...)
 if not ok then
 warn("[NexHub] Error:", result)
 end
 return ok, result
end

---------------------------------------------------------------
-- TABLE HELPERS
---------------------------------------------------------------

function Utils.tableContains(tbl, value)
 for _, v in ipairs(tbl) do
 if v == value then return true end
 end
 return false
end

function Utils.tableKeys(tbl)
 local keys = {}
 for k in pairs(tbl) do
 table.insert(keys, k)
 end
 return keys
end

function Utils.deepCopy(original)
 local copy = {}
 for k, v in pairs(original) do
 if type(v) == "table" then
 copy[k] = Utils.deepCopy(v)
 else
 copy[k] = v
 end
 end
 return copy
end

---------------------------------------------------------------
-- STRING HELPERS
---------------------------------------------------------------

function Utils.formatNumber(n)
 if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
 if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
 if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
 if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
 return tostring(n)
end

function Utils.formatTime(seconds)
 local h = math.floor(seconds / 3600)
 local m = math.floor((seconds % 3600) / 60)
 local s = math.floor(seconds % 60)
 if h > 0 then return string.format("%dh %dm %ds", h, m, s) end
 if m > 0 then return string.format("%dm %ds", m, s) end
 return string.format("%ds", s)
end

---------------------------------------------------------------
-- SIGNAL (simple event)
---------------------------------------------------------------

function Utils.createSignal()
 local signal = {}
 signal._bindables = {}

 function signal:Connect(fn)
 local connection = { _fn = fn, _connected = true }
 table.insert(signal._bindables, connection)
 function connection:Disconnect()
 self._connected = false
 end
 return connection
 end

 function signal:Fire(...)
 for _, conn in ipairs(signal._bindables) do
 if conn._connected then
 task.spawn(conn._fn, ...)
 end
 end
 end

 return signal
end


---------------------------------------------------------------
-- CORE: ANTI-AFK (inlined from core/antiafk.lua)
---------------------------------------------------------------

local AntiAfk = {}
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

AntiAfk._running = false
AntiAfk._thread = nil
AntiAfk._rejoinThread = nil
AntiAfk._stats = { actions = 0, rejoins = 0, lastAction = 0 }

---------------------------------------------------------------
-- ANTI-AFK
---------------------------------------------------------------

function AntiAfk.start(config)
 if AntiAfk._running then return end
 AntiAfk._running = true

 local interval = config.Timings.AntiAfkInterval or 60

 AntiAfk._thread = task.spawn(function()
 while AntiAfk._running do
 -- Method 1: VirtualUser click (most reliable)
 pcall(function()
 VirtualUser:CaptureController()
 VirtualUser:ClickButton2(Vector2.new())
 end)

 -- Method 2: Simulate movement
 pcall(function()
 local humanoid = LP.Character
 and LP.Character:FindFirstChildWhichIsA("Humanoid")
 if humanoid then
 humanoid.Jump = true
 end
 end)

 -- Method 3: Fire game's anti-AFK remote if available
 pcall(function()
 local Net = require(
 RS:WaitForChild("SharedModules"):WaitForChild("Networking")
 )
 if Net.AntiAfk and Net.AntiAfk.RequestHop then
 -- Only fire if idle long enough (game tracks this)
 end
 end)

 AntiAfk._stats.actions += 1
 AntiAfk._stats.lastAction = os.time()
 task.wait(interval)
 end
 end)

 -- Also handle the idle kicked event
 LP.Idled:Connect(function()
 pcall(function()
 VirtualUser:CaptureController()
 VirtualUser:ClickButton2(Vector2.new())
 end)
 end)

 print("[NexHub] Anti-AFK started (interval: " .. interval .. "s)")
end

function AntiAfk.stop()
 AntiAfk._running = false
 if AntiAfk._thread then
 task.cancel(AntiAfk._thread)
 AntiAfk._thread = nil
 end
end

---------------------------------------------------------------
-- AUTO-REJOIN
---------------------------------------------------------------

function AntiAfk.startAutoRejoin(config)
 if AntiAfk._rejoinThread then return end

 local delay = config.Timings.RejoinDelay or 5

 -- Handle disconnection
 game:GetService("CoreGui").RobloxPromptGui.promptOverlay
 .ChildAdded:Connect(function(child)
 if child.Name == "ErrorPrompt" or child.Name == "TeleportPrompt" then
 AntiAfk._stats.rejoins += 1
 task.wait(delay)
 pcall(function()
 game:GetService("TeleportService"):TeleportToPlaceInstance(
 game.PlaceId,
 game.JobId,
 LP
 )
 end)
 end
 end)

 -- Handle kick messages
 game:GetService("GuiService").ErrorMessageChanged:Connect(function()
 AntiAfk._stats.rejoins += 1
 task.wait(delay)
 pcall(function()
 game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
 end)
 end)

 -- Handle character death (auto-respawn)
 LP.CharacterAdded:Connect(function(char)
 local humanoid = char:WaitForChild("Humanoid", 10)
 if humanoid then
 humanoid.Died:Connect(function()
 task.wait(3)
 pcall(function()
 LP:LoadCharacter()
 end)
 end)
 end
 end)

 print("[NexHub] Auto-Rejoin enabled")
end

function AntiAfk.getStats()
 return AntiAfk._stats
end


---------------------------------------------------------------
-- MODULE REGISTRY
---------------------------------------------------------------

local Modules = {}
local Running = {}

local function startModule(name)
 if Running[name] then return end
 local mod = Modules[name]
 if mod and mod.start then
 mod.start(Config, Networking, Utils)
 Running[name] = true
 print("[NexHub] Started:", name)
 end
end

local function stopModule(name)
 if not Running[name] then return end
 local mod = Modules[name]
 if mod and mod.stop then
 mod.stop()
 Running[name] = false
 print("[NexHub] Stopped:", name)
 end
end

local function toggleModule(name)
 if Running[name] then stopModule(name) else startModule(name) end
 Config.Features[name] = Running[name]
end

---------------------------------------------------------------
-- MODULE: AUTO HARVEST
---------------------------------------------------------------

Modules.AutoHarvest = {}
do
 local M = Modules.AutoHarvest
 local Harvest = M
 local Players = game:GetService("Players")
 Harvest._running = false
 Harvest._thread = nil
 Harvest._connections = {}
 Harvest._stats = { harvested = 0, scans = 0, errors = 0 }

 ---------------------------------------------------------------
 -- GET MY PLOT (dynamic)
 ---------------------------------------------------------------

 function Harvest._getMyPlot()
 local lp = Players.LocalPlayer
 if not lp then return nil end
 local plotId = lp:GetAttribute("PlotId")
 if not plotId then return nil end
 local gardens = workspace:FindFirstChild("Gardens")
 if not gardens then return nil end
 return gardens:FindFirstChild("Plot" .. tostring(plotId))
 end

 function Harvest._isAlive()
 local lp = Players.LocalPlayer
 if not lp then return false end
 local char = lp.Character
 if not char then return false end
 local hum = char:FindFirstChildWhichIsA("Humanoid")
 return hum and hum.Health > 0
 end

 function Harvest._isHarvestable(fruitModel)
 if not fruitModel or not fruitModel.Parent then return false end
 local harvestPart = fruitModel:FindFirstChild("HarvestPart")
 if not harvestPart then return false end
 local prompt = harvestPart:FindFirstChild("HarvestPrompt")
 if not prompt then return false end
 if not prompt.Enabled then return false end
 return true
 end

 ---------------------------------------------------------------
 -- COLLECT ALL FRUITS ON MY PLOT (direct remote, no prompt)
 -- Two harvest paths:
 -- Multi: Plant → Fruits → FruitModel(HarvestPart.HarvestPrompt) → CollectFruit(plantId, fruitId)
 -- Single: Plant → HarvestPart.HarvestPrompt (no Fruits folder) → CollectFruit(plantId, "")
 ---------------------------------------------------------------

 function Harvest._collectAll(Net)
 if not Harvest._isAlive() then return 0 end

 local plot = Harvest._getMyPlot()
 if not plot then return 0 end
 local count = 0
 local plantsFolder = plot:FindFirstChild("Plants")
 if not plantsFolder then return 0 end
 for _, plantModel in ipairs(plantsFolder:GetChildren()) do
 if not Harvest._running then break end
 local plantId = plantModel:GetAttribute("PlantId")
 if not plantId then continue end

 -- Path A: Multi-harvest (has Fruits folder)
 local fruitsFolder = plantModel:FindFirstChild("Fruits")
 if fruitsFolder then
 for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
 if not Harvest._running then break end
 if not Harvest._isHarvestable(fruitModel) then continue end
 local fruitId = fruitModel:GetAttribute("FruitId")
 pcall(function()
 Net.fire("Garden.CollectFruit", plantId, fruitId or "")
 end)
 count += 1
 task.wait(0.1)
 end
 end

 -- Path B: Single-harvest (HarvestPrompt directly on plant)
 if Harvest._isHarvestable(plantModel) then
 pcall(function()
 Net.fire("Garden.CollectFruit", plantId, "")
 end)
 count += 1
 task.wait(0.1)
 end
 end
 return count
 end

 ---------------------------------------------------------------
 -- START
 ---------------------------------------------------------------

 function Harvest.start(config, Net, Utils)
 if Harvest._running then return end
 Harvest._running = true

 local interval = config.Timings.HarvestInterval or 0.5

 -- [METHOD 1] Listen for new fruits and collect immediately
 local fruitAddedConn = Net.on("Garden.FruitAdded", function(plantId, fruitId, fruitName, data)
 if not Harvest._running then return end
 if not Harvest._isAlive() then return end
 task.wait(0.15)
 pcall(function()
 Net.fire("Garden.CollectFruit", plantId, fruitId or "")
 end)
 Harvest._stats.harvested += 1
 end)
 if fruitAddedConn then
 table.insert(Harvest._connections, fruitAddedConn)
 end

 -- [METHOD 2] Periodic scan — walk garden tree, fire CollectFruit directly
 Harvest._thread = task.spawn(function()
 while Harvest._running do
 Harvest._stats.scans += 1
 local count = Harvest._collectAll(Net)
 Harvest._stats.harvested += count
 task.wait(interval)
 end
 end)

 print("[NexHub] Auto-Harvest started")
 end

 ---------------------------------------------------------------
 -- STOP / STATUS
 ---------------------------------------------------------------

 function Harvest.stop()
 Harvest._running = false
 if Harvest._thread then
 Harvest._thread = nil
 end
 for _, conn in ipairs(Harvest._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Harvest._connections = {}
 end

 function Harvest.getStats()
 return Harvest._stats
 end
end

---------------------------------------------------------------
-- MODULE: AUTO SELL
---------------------------------------------------------------

Modules.AutoSell = {}
do
 local M = Modules.AutoSell
 local Sell = M
Sell._running = false
Sell._thread = nil
Sell._connections = {}
Sell._stats = { sold = 0, totalEarned = 0, errors = 0 }

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Sell.start(config, Net, Utils)
 if Sell._running then return end
 Sell._running = true

 local interval = config.Timings.SellInterval or 5
 local sellConfig = config.Sell or {}

 Sell._thread = task.spawn(function()
 while Sell._running do
 Sell._autoSell(sellConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Auto-Sell started (mode: " .. (sellConfig.Mode or "all") .. ")")
end

---------------------------------------------------------------
-- AUTO SELL LOGIC
---------------------------------------------------------------

function Sell._autoSell(sellConfig, Net, Utils)
 -- Guard: skip if no fruits in backpack
 local lp = Players.LocalPlayer
 local bp = lp and lp:FindFirstChild("Backpack")
 local hasFruit = false
 if bp then
 for _, tool in ipairs(bp:GetChildren()) do
 if tool:IsA("Tool") and (tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit")) then
 hasFruit = true
 break
 end
 end
 end
 -- Also check character (equipped tool)
 if not hasFruit and lp and lp.Character then
 for _, tool in ipairs(lp.Character:GetChildren()) do
 if tool:IsA("Tool") and (tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit")) then
 hasFruit = true
 break
 end
 end
 end
 if not hasFruit then return end

 local mode = sellConfig.Mode or "all"

 if mode == "all" then
 -- Sell everything
 local ok = Net.fire("NPCS.SellAll")
 if ok then
 Sell._stats.sold += 1
 else
 Sell._stats.errors += 1
 end

 elseif mode == "below_threshold" then
 -- Sell individual fruits below value threshold
 Sell._sellBelowThreshold(sellConfig, Net, Utils)

 elseif mode == "keep_best" then
 -- Sell all except top N
 Sell._sellKeepBest(sellConfig, Net, Utils)
 end

 -- Use daily deal if configured
 if sellConfig.UseDailyDeal then
 Net.fire("NPCS.UseDailyDealAll")
 end
end

-- Sell fruits below a certain value threshold
function Sell._sellBelowThreshold(sellConfig, Net, Utils)
 local threshold = sellConfig.ValueThreshold or 100

 -- Get backpack items
 local items = Utils.getBackpackItems()
 for _, item in ipairs(items) do
 if item.Type == "HarvestedFruit" or string.find(item.Name, "Fruit") then
 -- Try to sell this individual fruit
 local ok = Net.fire("NPCS.SellFruit", item.Name)
 if ok then
 Sell._stats.sold += 1
 end
 end
 end
end

-- Sell all except keep top N valuable fruits
function Sell._sellKeepBest(sellConfig, Net, Utils)
 -- Just sell all for now - more complex logic needs inventory API
 local ok = Net.fire("NPCS.SellAll")
 if ok then
 Sell._stats.sold += 1
 end
end

---------------------------------------------------------------
-- MANUAL SELL ALL
---------------------------------------------------------------

function Sell.sellAll(Net)
 local ok = Net.fire("NPCS.SellAll")
 if ok then
 Sell._stats.sold += 1
 end
 return ok
end

---------------------------------------------------------------
-- SELL SPECIFIC FRUIT
---------------------------------------------------------------

function Sell.sellFruit(Net, fruitName)
 local ok = Net.fire("NPCS.SellFruit", fruitName)
 if ok then
 Sell._stats.sold += 1
 end
 return ok
end

---------------------------------------------------------------
-- USE DAILY DEAL
---------------------------------------------------------------

function Sell.useDailyDeal(Net, single)
 if single then
 return Net.fire("NPCS.UseDailyDealSingle")
 else
 return Net.fire("NPCS.UseDailyDealAll")
 end
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Sell.stop()
 Sell._running = false
 for _, conn in ipairs(Sell._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Sell._connections = {}
end

function Sell.getStats()
 return Sell._stats
end

end

---------------------------------------------------------------
-- MODULE: AUTO WATER
---------------------------------------------------------------

Modules.AutoWater = {}
do
 local M = Modules.AutoWater
 local Water = M
Water._running = false
Water._thread = nil
Water._connections = {}
Water._stats = { watered = 0, scans = 0, errors = 0 }

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Water.start(config, Net, Utils)
 if Water._running then return end
 Water._running = true

 local interval = config.Timings.WaterInterval or 3

 Water._thread = task.spawn(function()
 while Water._running do
 Water._waterPlants(config, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Auto-Water started")
end

---------------------------------------------------------------
-- WATER PLANTS
---------------------------------------------------------------

function Water._waterPlants(config, Net, Utils)
 local garden = Utils.getMyGarden()
 if not garden then return end

 Water._stats.scans += 1
 local plants = Utils.getPlantsInGarden(garden)

 for _, plant in ipairs(plants) do
 local info = Utils.getPlantInfo(plant)
 if info then
 -- Check if plant needs water (Growth < 1 and not fully grown)
 local needsWater = info.Growth < 1

 if needsWater or config.Water.WaterAll then
 -- Get plant position for watering can
 local rootPart = plant:FindFirstChildWhichIsA("BasePart")
 if rootPart then
 -- METHOD 1: Use watering can remote
 local ok = Net.fire("WateringCan.UseWateringCan", rootPart.Position)
 if ok then
 Water._stats.watered += 1
 else
 Water._stats.errors += 1
 end
 end
 end
 end
 end
end

---------------------------------------------------------------
-- AUTO SPRINKLER (place sprinklers in garden)
---------------------------------------------------------------

function Water.placeSprinkler(Net, Utils, sprinklerType)
 local garden = Utils.getMyGarden()
 if not garden then return false end

 -- Find center of garden
 local spawnPoint = garden:FindFirstChild("SpawnPoint")
 local position = spawnPoint and spawnPoint.Position or Vector3.new(0, 0, 0)

 local ok = Net.fire("Place.PlaceSprinkler", position, sprinklerType or "Common Sprinkler")
 return ok
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Water.stop()
 Water._running = false
 for _, conn in ipairs(Water._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Water._connections = {}
end

function Water.getStats()
 return Water._stats
end

end

---------------------------------------------------------------
-- MODULE: AUTO PLANT
-- Reference: Controllers_PlantController.module.lua
-- Remote: Plant.PlantSeed(position: Vector3, seedName: String, toolInstance: Instance)
-- Plant areas: CollectionService:GetTagged("PlantArea")
-- Seed tool: Character tool with "SeedTool" attribute
-- Flow: find seed in backpack → equip → fire PlantSeed
---------------------------------------------------------------

Modules.AutoPlant = {}
do
 local M = Modules.AutoPlant
 local Plant = M
 local Players = game:GetService("Players")
 local CollectionService = game:GetService("CollectionService")
Plant._running = false
Plant._thread = nil
Plant._connections = {}
Plant._stats = { planted = 0, scans = 0, errors = 0, noSeeds = 0, equipped = 0 }

---------------------------------------------------------------
-- GET EQUIPPED SEED TOOL (matching decompiled GetEquippedTool)
-- Must be a Tool with "SeedTool" attribute = seed name
---------------------------------------------------------------

function Plant._getEquippedSeed()
 local lp = Players.LocalPlayer
 local char = lp and lp.Character
 if not char then return nil, nil end
 local tool = char:FindFirstChildWhichIsA("Tool")
 if not tool then return nil, nil end
 local seedName = tool:GetAttribute("SeedTool")
 if not seedName then return nil, nil end
 return seedName, tool
end

---------------------------------------------------------------
-- FIND SEED TOOLS IN BACKPACK
-- Returns list of {tool, seedName} sorted by seed name
---------------------------------------------------------------

function Plant._findSeedsInBackpack(preferSeed)
 local lp = Players.LocalPlayer
 local bp = lp and lp:FindFirstChild("Backpack")
 if not bp then return {} end
 local seeds = {}
 for _, tool in ipairs(bp:GetChildren()) do
 if tool:IsA("Tool") then
 local sn = tool:GetAttribute("SeedTool")
 if sn then
 table.insert(seeds, { tool = tool, seedName = sn })
 end
 end
 end
 -- Sort: preferred seed first, then alphabetical
 table.sort(seeds, function(a, b)
 if preferSeed then
 local aMatch = (a.seedName == preferSeed) and 1 or 0
 local bMatch = (b.seedName == preferSeed) and 1 or 0
 if aMatch ~= bMatch then return aMatch > bMatch end
 end
 return a.seedName < b.seedName
 end)
 return seeds
end

---------------------------------------------------------------
-- EQUIP SEED TOOL FROM BACKPACK
-- Uses Humanoid:EquipTool() — same as game's internal flow
-- Returns seedName, toolInstance on success
---------------------------------------------------------------

function Plant._equipSeed(preferSeed)
 local lp = Players.LocalPlayer
 local char = lp and lp.Character
 if not char then return nil, nil end
 local humanoid = char:FindFirstChildWhichIsA("Humanoid")
 if not humanoid then return nil, nil end

 -- Check if already equipped
 local sn, tool = Plant._getEquippedSeed()
 if sn then return sn, tool end

 -- Find seed in backpack
 local seeds = Plant._findSeedsInBackpack(preferSeed)
 if #seeds == 0 then return nil, nil end

 -- Equip first seed (preferred or first available)
 local target = seeds[1]
 local ok = pcall(function()
 humanoid:EquipTool(target.tool)
 end)
 if not ok then return nil, nil end

 -- Wait for tool to appear in character
 local waited = 0
 while waited < 2 do
 task.wait(0.1)
 waited += 0.1
 local equipped = char:FindFirstChild(target.tool.Name)
 if equipped and equipped:IsA("Tool") and equipped:GetAttribute("SeedTool") then
 Plant._stats.equipped += 1
 return target.seedName, target.tool
 end
 end

 return nil, nil
end

---------------------------------------------------------------
-- UNEQUIP CURRENT TOOL (back to backpack)
---------------------------------------------------------------

function Plant._unequipTool()
 local lp = Players.LocalPlayer
 local char = lp and lp.Character
 if not char then return end
 local tool = char:FindFirstChildWhichIsA("Tool")
 if not tool then return end
 pcall(function()
 tool.Parent = lp:FindFirstChild("Backpack")
 end)
end

---------------------------------------------------------------
-- GET MY PLOT (matching decompiled GetPlayerPlot)
---------------------------------------------------------------

function Plant._getMyPlot()
 local lp = Players.LocalPlayer
 if not lp then return nil end
 local plotId = lp:GetAttribute("PlotId")
 if not plotId then return nil end
 return workspace:FindFirstChild("Gardens") and workspace.Gardens:FindFirstChild("Plot" .. tostring(plotId))
end

---------------------------------------------------------------
-- CHECK IF POSITION IS EMPTY (no existing plant within range)
-- Returns true if position is clear
---------------------------------------------------------------

function Plant._isPosEmpty(pos, myPlot, minDist)
 minDist = minDist or 2.5 -- minimum spacing between plants
 local plantsFolder = myPlot:FindFirstChild("Plants")
 if not plantsFolder then return true end
 for _, plantModel in ipairs(plantsFolder:GetChildren()) do
 local plantId = plantModel:GetAttribute("PlantId")
 if plantId then
 local root = plantModel.PrimaryPart or plantModel:FindFirstChildWhichIsA("BasePart")
 if root then
 local dist = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
 if dist < minDist then
 return false
 end
 end
 end
 end
 return true
end

---------------------------------------------------------------
-- GENERATE GRID POSITIONS FROM A PLANTAREA PART
-- Covers the entire part surface with evenly spaced points
-- spacing: studs between each grid point (default 3)
---------------------------------------------------------------

function Plant._generateGridFromPart(part, spacing)
 spacing = spacing or 3
 local positions = {}
 local size = part.Size
 local cf = part.CFrame

 -- Calculate grid steps in local X and Z axes
 local halfX = size.X / 2
 local halfZ = size.Z / 2
 local stepsX = math.max(1, math.floor(size.X / spacing))
 local stepsZ = math.max(1, math.floor(size.Z / spacing))

 -- Generate evenly spaced points across the part surface
 for ix = 0, stepsX do
 for iz = 0, stepsZ do
 -- Map to local coordinates: -halfX to +halfX
 local localX = -halfX + (ix / stepsX) * size.X
 local localZ = -halfZ + (iz / stepsZ) * size.Z
 -- Transform to world position (use top surface Y)
 local worldPos = cf * Vector3.new(localX, size.Y / 2, localZ)
 table.insert(positions, worldPos)
 end
 end
 return positions
end

---------------------------------------------------------------
-- FIND ALL EMPTY PLANT POSITIONS
-- 1. Get all PlantArea parts in my plot
-- 2. Generate grid across each part's surface
-- 3. Filter out positions too close to existing plants
-- Returns sorted list of empty world positions
---------------------------------------------------------------

function Plant._findEmptySpots(myPlot, spacing)
 spacing = spacing or 3

 -- Collect all PlantArea parts belonging to my plot
 local plantAreaParts = {}
 for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
 if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
 table.insert(plantAreaParts, part)
 end
 end

 -- Also check for PlantArea tagged via attribute (some plots use this)
 for _, desc in ipairs(myPlot:GetDescendants()) do
 if desc:IsA("BasePart") and desc:GetAttribute("PlantArea") then
 if not table.find(plantAreaParts, desc) then
 table.insert(plantAreaParts, desc)
 end
 end
 end

 if #plantAreaParts == 0 then
 -- Fallback: use GardenTotalArea if no PlantArea found
 for _, part in ipairs(CollectionService:GetTagged("GardenTotalArea")) do
 if part:IsA("BasePart") and part:IsDescendantOf(myPlot) then
 table.insert(plantAreaParts, part)
 end
 end
 end

 -- Generate grid positions across all parts
 local allPositions = {}
 for _, part in ipairs(plantAreaParts) do
 local grid = Plant._generateGridFromPart(part, spacing)
 for _, pos in ipairs(grid) do
 table.insert(allPositions, pos)
 end
 end

 -- Filter: only keep empty positions
 local emptySpots = {}
 for _, pos in ipairs(allPositions) do
 if Plant._isPosEmpty(pos, myPlot) then
 table.insert(emptySpots, pos)
 end
 end

 -- Sort by distance from plot center for consistent planting order
 local plotCenter = myPlot.PrimaryPart and myPlot.PrimaryPart.Position
 or (myPlot:FindFirstChild("SpawnPoint") and myPlot.SpawnPoint.Position)
 or Vector3.zero
 table.sort(emptySpots, function(a, b)
 local da = (Vector2.new(a.X - plotCenter.X, a.Z - plotCenter.Z)).Magnitude
 local db = (Vector2.new(b.X - plotCenter.X, b.Z - plotCenter.Z)).Magnitude
 return da < db
 end)

 return emptySpots
end

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Plant.start(config, Net, Utils)
 if Plant._running then return end
 Plant._running = true

 local interval = config.Timings.PlantInterval or 5
 local plantConfig = config.Plant or {}

 Plant._thread = task.spawn(function()
 while Plant._running do
 Plant._autoPlant(plantConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Auto-Plant started")
end

---------------------------------------------------------------
-- AUTO PLANT LOGIC
-- Flow: equip seed from backpack → fill all empty spots → unequip
---------------------------------------------------------------

function Plant._autoPlant(plantConfig, Net, Utils)
 Plant._stats.scans += 1

 local preferSeed = plantConfig.PreferSeed -- optional: preferred seed name

 -- Step 1: USE SEED — equip from backpack before planting
 local seedName, toolInstance = Plant._equipSeed(preferSeed)
 if not seedName then
 Plant._stats.noSeeds += 1
 return
 end

 -- Step 2: Get plot
 local myPlot = Plant._getMyPlot()
 if not myPlot then
 Plant._unequipTool()
 return
 end

 -- Step 3: Find empty spots — grid scan across all PlantArea parts
 local spacing = plantConfig.GridSpacing or 3
 local spots = Plant._findEmptySpots(myPlot, spacing)
 if #spots == 0 then
 Plant._unequipTool()
 return
 end

 print("[NexHub] Found", #spots, "empty spots in plot")

 -- Step 4: Plant in ALL empty spots (fill the entire plot)
 local planted = 0
 for _, pos in ipairs(spots) do
 if not Plant._running then break end

 -- Verify still equipped before each fire
 local curSn, curTool = Plant._getEquippedSeed()
 if not curSn then
 -- Re-equip if tool got consumed
 seedName, toolInstance = Plant._equipSeed(preferSeed)
 if not seedName then break end
 end

 local ok = pcall(function()
 Net.fire("Plant.PlantSeed", pos, seedName, toolInstance)
 end)

 if ok then
 planted += 1
 Plant._stats.planted += 1
 print("[NexHub] Planted:", seedName, "at", tostring(pos))
 else
 Plant._stats.errors += 1
 end

 task.wait(0.3) -- small delay between plants
 end

 -- Step 5: Unequip after planting
 Plant._unequipTool()

 if planted > 0 then
 print("[NexHub] Auto-Plant cycle: planted", planted, seedName)
 end
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Plant.stop()
 Plant._running = false
 for _, conn in ipairs(Plant._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Plant._connections = {}
end

function Plant.getStats()
 return Plant._stats
end

end

---------------------------------------------------------------
-- MODULE: RESTOCK SNIPER
---------------------------------------------------------------

Modules.RestockSniper = {}
do
 local M = Modules.RestockSniper
 local Restock = M
Restock._running = false
Restock._thread = nil
Restock._connections = {}
Restock._stats = { bought = 0, scanned = 0, moneySpent = 0, errors = 0, skipped = 0 }

-- Seed prices for affordability check
local SeedPrices = {
 ["Carrot"] = 1, ["Strawberry"] = 10, ["Blueberry"] = 25, ["Tulip"] = 40,
 ["Tomato"] = 200, ["Apple"] = 400, ["Bamboo"] = 700, ["Corn"] = 2500,
 ["Cactus"] = 5000, ["Pineapple"] = 10000, ["Mushroom"] = 15000,
 ["Green Bean"] = 20000, ["Banana"] = 30000, ["Grape"] = 50000,
 ["Coconut"] = 70000, ["Mango"] = 85000, ["Dragon Fruit"] = 120000,
 ["Acorn"] = 200000, ["Cherry"] = 250000, ["Sunflower"] = 300000,
 ["Venus Fly Trap"] = 400000, ["Poison Apple"] = 400000,
 ["Pomegranate"] = 2000000, ["Ghost Pepper"] = 2800000,
 ["Poison Ivy"] = 2800000, ["Moon Bloom"] = 7000000,
 ["Dragon's Breath"] = 9000000,
 ["Baby Cactus"] = 1, ["Glow Mushroom"] = 1, ["Romanesco"] = 1,
 ["Horned Melon"] = 1, ["Gold"] = 1,
}

---------------------------------------------------------------
-- GET STOCK VALUES
---------------------------------------------------------------

function Restock._getStockFolder()
 local ok, folder = pcall(function()
 return game:GetService("ReplicatedStorage")
 :WaitForChild("StockValues", 5)
 :WaitForChild("SeedShop", 5)
 :WaitForChild("Items", 5)
 end)
 return ok and folder or nil
end

function Restock._getStock(seedName)
 local folder = Restock._getStockFolder()
 if not folder then return -1 end -- unknown
 local val = folder:FindFirstChild(seedName)
 if not val then return 0 end
 if val:IsA("ValueBase") then return (val.Value or 0) end
 -- might be a NumberValue / IntValue directly
 return 0
end

function Restock._getRestockTime()
 local ok, val = pcall(function()
 local unix = game:GetService("ReplicatedStorage")
 :WaitForChild("StockValues", 5)
 :WaitForChild("SeedShop", 5)
 :WaitForChild("UnixNextRestock", 5)
 return unix.Value or 0
 end)
 return ok and val or 0
end

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Restock.start(config, Net, Utils)
 if Restock._running then return end
 Restock._running = true

 local interval = config.Timings.RestockPollInterval or 1
 local restockConfig = config.Restock or {}

 Restock._thread = task.spawn(function()
 while Restock._running do
 Restock._pollAndBuy(restockConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Restock Sniper started (targets: " ..
 #(restockConfig.TargetSeeds or {}) .. " seeds)")
end

---------------------------------------------------------------
-- POLL AND BUY — DRAIN STOCK
-- For each target seed: buy in loop until stock == 0
---------------------------------------------------------------

function Restock._pollAndBuy(restockConfig, Net, Utils)
 Restock._stats.scanned += 1

 local targets = restockConfig.TargetSeeds or {}
 if #targets == 0 then return end

 local blacklist = {}
 for _, name in ipairs(restockConfig.BlacklistedSeeds or {}) do
 blacklist[name] = true
 end

 for _, seedName in ipairs(targets) do
 if not Restock._running then break end
 if blacklist[seedName] then continue end

 -- Affordability check
 local price = SeedPrices[seedName] or 0
 local sheckles = Utils.getSheckles()
 if price > 0 and sheckles < price then
 Restock._stats.skipped += 1
 continue -- can't afford
 end

 local stock = Restock._getStock(seedName)
 if stock == 0 then
 Restock._stats.skipped += 1
 continue -- out of stock
 end

 -- DRAIN: buy in loop until stock empty
 local buyCount = 0
 local maxBuys = (stock > 0 and stock) or 50 -- stock=-1 unknown, try 50
 for i = 1, maxBuys do
 if not Restock._running then break end

 -- Re-check affordability inside loop
 if price > 0 and Utils.getSheckles() < price then break end

 local prevStock = Restock._getStock(seedName)
 Restock._buySeed(Net, seedName)
 task.wait(0.15) -- wait for server to update stock
 local newStock = Restock._getStock(seedName)

 if newStock < prevStock then
 buyCount += 1
 Restock._stats.bought += 1
 else
 break -- stock didn't change, buy failed
 end
 end

 if buyCount > 0 then
 print("[NexHub] Drained:", seedName, "x" .. buyCount, "(stock was:", stock .. ")")
 end
 end
end

---------------------------------------------------------------
-- BUY SEED (actual remote) — returns ok, price
---------------------------------------------------------------

function Restock._buySeed(Net, seedName)
 local ok, err = pcall(function()
 Net.fire("SeedShop.PurchaseSeed", seedName)
 end)
 if ok then
 return true, 0
 end
 Restock._stats.errors += 1
 return false, 0
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Restock.stop()
 Restock._running = false
 Restock._thread = nil
 for _, conn in ipairs(Restock._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Restock._connections = {}
end

function Restock.getStats()
 return Restock._stats
end
end

---------------------------------------------------------------
-- MODULE: MUTATION TRACKER
---------------------------------------------------------------

Modules.MutationTracker = {}
do
 local M = Modules.MutationTracker
 local Mutation = M
Mutation._running = false
Mutation._thread = nil
Mutation._connections = {}
Mutation._stats = { tracked = 0, alerts = 0, totalValue = 0 }
Mutation._mutationLog = {}

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Mutation.start(config, Net, Utils)
 if Mutation._running then return end
 Mutation._running = true

 local interval = config.Timings.MutationScanInterval or 3
 local mutConfig = config.Mutation or {}

 -- Load mutation data for price multipliers
 local RS = game:GetService("ReplicatedStorage")
 local mutationData = {}
 pcall(function()
 local shared = RS:WaitForChild("SharedModules", 10)
 if shared then
 local mData = shared:FindFirstChild("MutationData")
 if mData then
 mutationData = require(mData)
 end
 end
 end)

 -- Listen for real-time mutation events
 local plantMutConn = Net.on("Garden.PlantMutationUpdated",
 function(plantId, mutation)
 Mutation._onMutation("plant", plantId, mutation, mutConfig, Utils)
 end
 )
 if plantMutConn then
 table.insert(Mutation._connections, plantMutConn)
 end

 local fruitMutConn = Net.on("Garden.FruitMutationUpdated",
 function(plantId, fruitId, mutation)
 Mutation._onMutation("fruit", plantId, mutation, mutConfig, Utils)
 end
 )
 if fruitMutConn then
 table.insert(Mutation._connections, fruitMutConn)
 end

 -- Also listen for plant growth (sometimes mutation comes with growth update)
 local growthConn = Net.on("Garden.PlantGrowthUpdated",
 function(plantId, growth, size, mutation)
 if mutation and mutation ~= "" then
 Mutation._onMutation("growth", plantId, mutation, mutConfig, Utils)
 end
 end
 )
 if growthConn then
 table.insert(Mutation._connections, growthConn)
 end

 -- Periodic scan of own garden
 Mutation._thread = task.spawn(function()
 while Mutation._running do
 Mutation._scanGarden(mutConfig, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Mutation Tracker started")
end

---------------------------------------------------------------
-- ON MUTATION EVENT
---------------------------------------------------------------

function Mutation._onMutation(source, plantId, mutation, config, Utils)
 if not mutation or mutation == "" then return end

 Mutation._stats.tracked += 1

 local entry = {
 source = source,
 plantId = plantId,
 mutation = mutation,
 time = os.time(),
 priceMult = config.PriceMultipliers[mutation] or 1,
 }

 table.insert(Mutation._mutationLog, entry)

 -- Keep log manageable
 if #Mutation._mutationLog > 500 then
 table.remove(Mutation._mutationLog, 1)
 end

 -- Check if this is an alert-worthy mutation
 local isAlert = false
 if config.TrackAll then
 isAlert = true
 else
 for _, name in ipairs(config.AlertMutations or {}) do
 if name == mutation then
 isAlert = true
 break
 end
 end
 end

 if isAlert then
 Mutation._stats.alerts += 1
 local mult = config.PriceMultipliers[mutation] or 1

 local msg = string.format("[%s] %s mutation: %s (x%d value)",
 source, tostring(plantId), mutation, mult)

 if config.LogToConsole then
 print("[NexHub] " .. msg)
 end

 Config.Notify(" Mutation Detected!", msg, 8)

 -- Play sound if available
 pcall(function()
 local SoundService = game:GetService("SoundService")
 local sound = Instance.new("Sound")
 sound.SoundId = "rbxassetid://6518811702" -- notification sound
 sound.Volume = 0.5
 sound.Parent = SoundService
 sound:Play()
 game:GetService("Debris"):AddItem(sound, 3)
 end)
 end
end

---------------------------------------------------------------
-- SCAN GARDEN FOR EXISTING MUTATIONS
---------------------------------------------------------------

function Mutation._scanGarden(config, Utils)
 local garden = Utils.getMyGarden()
 if not garden then return end

 local plants = Utils.getPlantsInGarden(garden)
 for _, plant in ipairs(plants) do
 local info = Utils.getPlantInfo(plant)
 if info and info.Mutation and info.Mutation ~= "" then
 -- Already tracked mutations are skipped
 -- This is mainly for initial discovery
 Mutation._stats.tracked += 1
 end
 end
end

---------------------------------------------------------------
-- GET MUTATION PRICE MULTIPLIER
---------------------------------------------------------------

function Mutation.getPriceMultiplier(mutationName, config)
 if config and config.PriceMultipliers then
 return config.PriceMultipliers[mutationName] or 1
 end
 return 1
end

---------------------------------------------------------------
-- GET MUTATION LOG
---------------------------------------------------------------

function Mutation.getLog()
 return Mutation._mutationLog
end

function Mutation.getLogByMutation(mutationName)
 local filtered = {}
 for _, entry in ipairs(Mutation._mutationLog) do
 if entry.mutation == mutationName then
 table.insert(filtered, entry)
 end
 end
 return filtered
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Mutation.stop()
 Mutation._running = false
 for _, conn in ipairs(Mutation._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Mutation._connections = {}
end

function Mutation.getStats()
 return Mutation._stats
end

end

---------------------------------------------------------------
-- MODULE: WEATHER BOT
---------------------------------------------------------------

Modules.WeatherBot = {}
do
 local M = Modules.WeatherBot
 local Weather = M
Weather._running = false
Weather._thread = nil
Weather._connections = {}
Weather._stats = { events = 0, alerts = 0, scans = 0 }
Weather._currentWeather = "Unknown"
Weather._currentPhase = "Unknown"
Weather._weatherLog = {}

---------------------------------------------------------------
-- WEATHER TYPES (from decompiled TimeCycleController)
---------------------------------------------------------------

Weather.Phases = {
 Day = { color = "", value = "Day" },
 Sunset = { color = "", value = "Sunset" },
 Moon = { color = "", value = "Moon" },
 Bloodmoon = { color = "", value = "Bloodmoon", rare = true },
 Goldmoon = { color = "", value = "Goldmoon", rare = true },
 Rainbow = { color = "", value = "Rainbow", rare = true },
 Chained = { color = "", value = "Chained Moon", rare = true },
 Pizza = { color = "", value = "Pizza Moon" },
}

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Weather.start(config, Net, Utils)
 if Weather._running then return end
 Weather._running = true

 local interval = config.Timings.WeatherPollInterval or 5
 local weatherConfig = config.Weather or {}

 -- Listen for weather effect events
 local weatherEvents = {
 "WeatherEffects.BloodmoonBeam",
 "WeatherEffects.RainbowStart",
 "WeatherEffects.RainbowEnd",
 "WeatherEffects.GoldMoonStrike",
 "WeatherEffects.RainbowMoonStrike",
 "WeatherEffects.BlizzardStart",
 "WeatherEffects.BlizzardEnd",
 "WeatherEffects.ShootingStar",
 "WeatherEffects.ChainPull",
 }

 for _, eventPath in ipairs(weatherEvents) do
 local conn = Net.on(eventPath, function(...)
 Weather._onWeatherEvent(eventPath, weatherConfig, Utils, ...)
 end)
 if conn then
 table.insert(Weather._connections, conn)
 end
 end

 -- Listen for time cycle changes
 local RS = game:GetService("ReplicatedStorage")
 local nightValue = RS:FindFirstChild("Night")
 if nightValue then
 local conn = nightValue.Changed:Connect(function(isNight)
 if isNight then
 Weather._currentPhase = "Night"
 Weather._logEvent("Night", "Night cycle started")
 else
 Weather._currentPhase = "Day"
 Weather._logEvent("Day", "Day cycle started")
 end
 end)
 table.insert(Weather._connections, conn)
 end

 -- Periodic scan of weather state
 Weather._thread = task.spawn(function()
 while Weather._running do
 Weather._scanWeather(weatherConfig, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Weather Bot started")
end

---------------------------------------------------------------
-- ON WEATHER EVENT
---------------------------------------------------------------

function Weather._onWeatherEvent(eventPath, config, Utils, ...)
 local args = {...}
 Weather._stats.events += 1

 -- Extract weather type from event path
 local weatherType = eventPath:match("WeatherEffects%.(.+)")
 if not weatherType then return end

 -- Determine if this is an alert-worthy event
 local isSpecial = false
 for _, name in ipairs(config.AlertEvents or {}) do
 if weatherType:match(name) then
 isSpecial = true
 break
 end
 end

 -- Alert for all start events
 if weatherType:match("Start") or weatherType:match("Strike") or
 weatherType:match("Beam") or weatherType:match("Star") then
 isSpecial = true
 end

 if isSpecial then
 Weather._stats.alerts += 1
 local emoji = ""
 for _, phase in pairs(Weather.Phases) do
 if weatherType:match(phase.value) then
 emoji = phase.color
 break
 end
 end

 local msg = emoji .. " " .. weatherType .. " event detected!"
 print("[NexHub] " .. msg)
 Config.Notify("Weather Event!", msg, 10)

 -- Execute configured action
 local action = config.Actions and config.Actions[weatherType]
 if action == "harvest_priority" then
 print("[NexHub] Priority harvest triggered by weather event")
 end

 -- Play sound
 if config.PlaySound then
 pcall(function()
 local SoundService = game:GetService("SoundService")
 local sound = Instance.new("Sound")
 sound.SoundId = "rbxassetid://6518811702"
 sound.Volume = 0.8
 sound.Parent = SoundService
 sound:Play()
 game:GetService("Debris"):AddItem(sound, 3)
 end)
 end
 end

 Weather._logEvent(weatherType, "Weather event fired")
end

---------------------------------------------------------------
-- SCAN WEATHER STATE
---------------------------------------------------------------

function Weather._scanWeather(config, Utils)
 Weather._stats.scans += 1

 -- Check moon phase from workspace or ReplicatedStorage
 local RS = game:GetService("ReplicatedStorage")

 -- Check if night
 local isNight = Utils.isNight()

 -- Try to read current moon phase
 local moonPhase = nil
 pcall(function()
 local lighting = game:GetService("Lighting")
 -- Some games store weather in lighting attributes
 moonPhase = lighting:GetAttribute("MoonPhase")
 or lighting:GetAttribute("CurrentPhase")
 end)

 -- Check workspace for weather indicators
 pcall(function()
 local weatherFolder = workspace:FindFirstChild("Weather")
 or workspace:FindFirstChild("WeatherEffects")
 if weatherFolder then
 for _, child in ipairs(weatherFolder:GetChildren()) do
 if child:IsA("BoolValue") and child.Value then
 Weather._currentWeather = child.Name
 end
 end
 end
 end)

 -- Update phase
 if isNight and Weather._currentPhase == "Day" then
 Weather._currentPhase = "Night"
 Weather._logEvent("Phase", "Transition to Night")
 elseif not isNight and Weather._currentPhase ~= "Day" then
 Weather._currentPhase = "Day"
 Weather._logEvent("Phase", "Transition to Day")
 end
end

---------------------------------------------------------------
-- LOG
---------------------------------------------------------------

function Weather._logEvent(eventType, description)
 table.insert(Weather._weatherLog, {
 type = eventType,
 desc = description,
 time = os.time(),
 phase = Weather._currentPhase,
 })
 if #Weather._weatherLog > 200 then
 table.remove(Weather._weatherLog, 1)
 end
end

---------------------------------------------------------------
-- GETTERS
---------------------------------------------------------------

function Weather.getCurrentWeather()
 return Weather._currentWeather
end

function Weather.getCurrentPhase()
 return Weather._currentPhase
end

function Weather.getLog()
 return Weather._weatherLog
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Weather.stop()
 Weather._running = false
 for _, conn in ipairs(Weather._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Weather._connections = {}
end

function Weather.getStats()
 return Weather._stats
end

end

---------------------------------------------------------------
-- MODULE: STEAL BOT
---------------------------------------------------------------

Modules.StealBot = {}
do
 local M = Modules.StealBot
 local Steal = M
 local Players = game:GetService("Players")
 Steal._running = false
 Steal._thread = nil
 Steal._connections = {}
 Steal._stats = { attempts = 0, stolen = 0, returned = 0, errors = 0, nightCycles = 0, skipped = 0 }

 ---------------------------------------------------------------
 -- GET MY PLOT ID
 ---------------------------------------------------------------

 function Steal._getMyPlotId()
 local lp = Players.LocalPlayer
 return lp and lp:GetAttribute("PlotId")
 end

 ---------------------------------------------------------------
 -- FIND STEALABLE PROMPTS ON OTHER PLAYERS' GARDENS
 -- Matching decompiled u87 guard logic:
 -- gate: Night.Value == true
 -- prompt.Enabled == true
 -- prompt:GetAttribute("Collected") != true
 -- StealPrompt + HoldDuration > 0 → SKIP (Bamboo)
 -- get PlantId/FruitId from parent fruit Model
 ---------------------------------------------------------------

 function Steal._findStealablePrompts(myPlotId)
 local results = {}
 local gardens = workspace:FindFirstChild("Gardens")
 if not gardens then return results end

 for _, garden in ipairs(gardens:GetChildren()) do
 local plotNum = tonumber(garden.Name:match("Plot(%d+)"))
 if plotNum and plotNum ~= myPlotId then
 local plantsFolder = garden:FindFirstChild("Plants")
 if plantsFolder then
 for _, plantModel in ipairs(plantsFolder:GetChildren()) do
 local fruitsFolder = plantModel:FindFirstChild("Fruits")
 if fruitsFolder then
 for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
 local prompt = fruitModel:FindFirstChild("StealPrompt", true)
 if not prompt then continue end
 if not prompt:IsA("ProximityPrompt") then continue end

 -- Guard: must be enabled, not already collected
 if not prompt.Enabled then continue end
 if prompt:GetAttribute("Collected") then continue end

 -- Guard: Bamboo has HoldDuration > 0, can't steal
 if prompt.HoldDuration > 0 then continue end

 -- Read attrs from fruit MODEL (not prompt)
 local userId = tonumber(fruitModel:GetAttribute("UserId"))
 local plantId = fruitModel:GetAttribute("PlantId")
 local fruitId = fruitModel:GetAttribute("FruitId")

 if userId and plantId then
 table.insert(results, {
 prompt = prompt,
 userId = userId,
 plantId = plantId,
 fruitId = fruitId or "",
 gardenName = garden.Name,
 })
 end
 end
 end
 end
 end
 end
 end
 return results
 end

 ---------------------------------------------------------------
 -- START
 ---------------------------------------------------------------

 function Steal.start(config, Net, Utils)
 if Steal._running then return end
 Steal._running = true

 local interval = config.Timings.StealInterval or 1.5
 local stealConfig = config.Steal or {}

 -- Listen for server steal confirmation events
 local startedConn = Net.on("Steal.StealStarted", function(fruitInstance)
 print("[NexHub] StealStarted confirmed by server:", fruitInstance and fruitInstance.Name or "?")
 end)
 local cancelledConn = Net.on("Steal.StealCancelled", function(fruitInstance)
 print("[NexHub] StealCancelled by server:", fruitInstance and fruitInstance.Name or "?")
 end)
 if startedConn then table.insert(Steal._connections, startedConn) end
 if cancelledConn then table.insert(Steal._connections, cancelledConn) end

 Steal._thread = task.spawn(function()
 local wasNight = false
 while Steal._running do
 local isNight = Utils.isNight()
 if isNight and not wasNight then
 Steal._stats.nightCycles += 1
 Steal._stats.attempts = 0 -- reset per night
 print("[NexHub] Night cycle started - Steal Bot active")
 end
 if isNight then
 Steal._stealLoop(stealConfig, Net, Utils)
 elseif wasNight then
 print("[NexHub] Day started - Steal Bot sleeping")
 pcall(function() Net.fire("Steal.CancelSteal") end)
 end
 wasNight = isNight
 task.wait(interval)
 end
 end)

 print("[NexHub] Steal Bot started (waits for night)")
 end

 ---------------------------------------------------------------
 -- STEAL LOOP
 ---------------------------------------------------------------

 function Steal._stealLoop(stealConfig, Net, Utils)
 local LP = Players.LocalPlayer

 -- If already carrying → return to plot first
 local carrying = LP:GetAttribute("CarryingStolenFruit")
 if carrying then
 Steal._returnFruit(Net, Utils)
 return
 end

 -- Max attempts guard
 local maxAttempts = stealConfig.MaxAttemptsPerNight or 20
 if Steal._stats.attempts >= maxAttempts then return end

 local myPlotId = Steal._getMyPlotId()
 if not myPlotId then return end

 local entries = Steal._findStealablePrompts(myPlotId)
 for _, entry in ipairs(entries) do
 if not Steal._running then break end
 if Steal._stats.attempts >= maxAttempts then break end

 -- Value filter
 if stealConfig.MinFruitValue and stealConfig.MinFruitValue > 0 then
 local sellValue = Steal._estimateValue(entry.plantId)
 if sellValue < stealConfig.MinFruitValue then
 Steal._stats.skipped += 1
 continue
 end
 end

 -- Attempt steal with full guard sequence
 local success = Steal._attemptSteal(entry, Net, Utils)
 if success then
 Steal._stats.stolen += 1
 print("[NexHub] Stolen from", entry.gardenName, "plant:", entry.plantId)
 Steal._returnFruit(Net, Utils)
 return
 end

 task.wait(0.5)
 end
 end

 ---------------------------------------------------------------
 -- ATTEMPT STEAL (matching decompiled flow)
 -- 1. Set Collected attr (anti-spam)
 -- 2. Simulate hold: InputHoldBegin → delay → InputHoldEnd
 -- 3. Fire BeginSteal(userId, plantId, fruitId)
 -- 4. Wait for CarryingStolenFruit
 -- 5. Fire CompleteSteal()
 -- 6. Clear Collected attr
 ---------------------------------------------------------------

 function Steal._attemptSteal(entry, Net, Utils)
 local prompt = entry.prompt
 if not prompt or not prompt.Parent then
 return false
 end
 if not prompt.Enabled then
 return false
 end
 if prompt:GetAttribute("Collected") then
 return false
 end

 Steal._stats.attempts += 1

 -- Step 1: Anti-spam lock
 pcall(function() prompt:SetAttribute("Collected", true) end)

 -- Step 2: Simulate hold (matching u10 function)
 local holdDuration = math.max(0.09, prompt.HoldDuration + 0.1)
 pcall(function()
 prompt:InputHoldBegin()
 end)
 task.wait(holdDuration)
 pcall(function()
 if prompt and prompt:IsDescendantOf(workspace) then
 prompt:InputHoldEnd()
 end
 end)

 -- Step 3: Fire steal remotes
 local fired = pcall(function()
 Net.fire("Steal.BeginSteal", entry.userId, entry.plantId, entry.fruitId)
 end)
 if not fired then
 pcall(function() prompt:SetAttribute("Collected", nil) end)
 Steal._stats.errors += 1
 return false
 end

 -- Step 4: Wait for server to confirm + carrying check
 task.wait(0.5)
 local LP = Players.LocalPlayer
 local nowCarrying = LP:GetAttribute("CarryingStolenFruit")

 -- Step 5: Complete steal if carrying
 if nowCarrying then
 pcall(function() Net.fire("Steal.CompleteSteal") end)
 end

 -- Step 6: Clear Collected lock after safe delay
 task.delay(holdDuration + 0.5, function()
 pcall(function()
 if prompt and prompt:IsDescendantOf(workspace) then
 prompt:SetAttribute("Collected", nil)
 end
 end)
 end)

 return nowCarrying and true or false
 end

 ---------------------------------------------------------------
 -- RETURN FRUIT TO OWN PLOT
 ---------------------------------------------------------------

 function Steal._returnFruit(Net, Utils)
 local LP = Players.LocalPlayer
 local carrying = LP:GetAttribute("CarryingStolenFruit")
 if not carrying then return end
 local garden = Utils.getMyGarden()
 if not garden then return end
 local hrp = Utils.getHumanoidRootPart()
 local spawnPoint = garden:FindFirstChild("SpawnPoint") or garden:FindFirstChildWhichIsA("BasePart")
 if hrp and spawnPoint then
 hrp.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0)
 task.wait(1)
 end
 Steal._stats.returned += 1
 print("[NexHub] Returned stolen fruit to plot")
 end

 ---------------------------------------------------------------
 -- ESTIMATE FRUIT VALUE
 ---------------------------------------------------------------

 function Steal._estimateValue(seedName)
 local values = {
 ["Carrot"] = 5, ["Strawberry"] = 3, ["Blueberry"] = 5,
 ["Tomato"] = 9, ["Apple"] = 12, ["Cactus"] = 40,
 ["Pineapple"] = 30, ["Banana"] = 35, ["Corn"] = 34,
 ["Grape"] = 45, ["Mango"] = 90, ["Coconut"] = 60,
 ["Cherry"] = 350, ["Pomegranate"] = 900,
 ["Dragon Fruit"] = 150, ["Mushroom"] = 13000,
 ["Sunflower"] = 1750, ["Venus Fly Trap"] = 3000,
 ["Moon Bloom"] = 9000, ["Dragon's Breath"] = 3400,
 ["Ghost Pepper"] = 2500, ["Lotus"] = 6500,
 }
 return values[seedName] or 0
 end

 ---------------------------------------------------------------
 -- STOP / STATUS
 ---------------------------------------------------------------

 function Steal.stop()
 Steal._running = false
 for _, conn in ipairs(Steal._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Steal._connections = {}
 end

 function Steal.getStats()
 return Steal._stats
 end
end

---------------------------------------------------------------
-- MODULE: AUTO BUY PET (Egg Hatch + Rarity Filter)
-- Reference: Controllers_EggHandleController, EggOpenController
-- Remotes: Egg.OpenEgg(eggName), Egg.ConfirmEgg(eggName, petName, size)
-- SellPet(petId)
-- Data: SharedModules.EggData, SharedData.PetData
---------------------------------------------------------------

Modules.AutoBuyPet = {}
do
 local M = Modules.AutoBuyPet
 local Pet = M
 local Players = game:GetService("Players")
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
Pet._running = false
Pet._thread = nil
Pet._connections = {}
Pet._stats = { hatched = 0, kept = 0, sold = 0, errors = 0, noEggs = 0 }

-- Rarity priority (lower = more common)
local RARITY_ORDER = {
 Common = 1, Uncommon = 2, Rare = 3,
 Legendary = 4, Epic = 4, Mythic = 5, Super = 6,
}

-- Load PetData for species rarity lookup
local PetData = nil
pcall(function()
 PetData = require(ReplicatedStorage:WaitForChild("SharedData"):WaitForChild("PetData"))
end)

-- Get rarity of a pet species from PetData
function Pet._getSpeciesRarity(petName)
 if PetData and PetData[petName] then
 return PetData[petName].Rarity or "Common"
 end
 return "Common"
end

-- Check if a pet passes the rarity filter
function Pet._passesFilter(petName, size, minRarity)
 local speciesRarity = Pet._getSpeciesRarity(petName)
 local gotRank = RARITY_ORDER[speciesRarity] or 1
 local wantRank = RARITY_ORDER[minRarity] or 1
 if gotRank < wantRank then return false end
 -- Also check size filter (Huge always passes)
 if size == "Huge" then return true end
 return true
end

---------------------------------------------------------------
-- FIND EGG TOOLS IN BACKPACK
-- Tools with "Egg" attribute = egg name
---------------------------------------------------------------

function Pet._findEggTools()
 local lp = Players.LocalPlayer
 local backpack = lp and lp:FindFirstChild("Backpack")
 if not backpack then return {} end
 local eggs = {}
 for _, tool in ipairs(backpack:GetChildren()) do
 if tool:IsA("Tool") then
 local eggName = tool:GetAttribute("Egg")
 if eggName and eggName ~= "" then
 table.insert(eggs, { tool = tool, eggName = eggName })
 end
 end
 end
 return eggs
end

---------------------------------------------------------------
-- HATCH ONE EGG
-- 1. Listen for ReplicateOpenEgg once
-- 2. Fire Egg.OpenEgg(eggName)
-- 3. Wait for result (petName, size, type)
-- 4. Fire Egg.ConfirmEgg(eggName, petName, size)
---------------------------------------------------------------

function Pet._hatchEgg(eggName, Net)
 local result = nil
 local done = false

 -- Hook ReplicateOpenEgg once
 local conn
 conn = Net.on("Egg.ReplicateOpenEgg", function(player, eName, petName, size, pos, petType, extra)
 if player == Players.LocalPlayer and eName == eggName then
 result = { petName = petName, size = size, petType = petType }
 done = true
 if conn then conn:Disconnect() end
 end
 end)

 -- Fire OpenEgg
 local fireOk = pcall(function()
 Net.fire("Egg.OpenEgg", eggName)
 end)

 if not fireOk then
 if conn then conn:Disconnect() end
 return nil
 end

 -- Wait for result (max 5s)
 local t = 0
 while not done and t < 5 do
 task.wait(0.1)
 t = t + 0.1
 end

 if conn then pcall(function() conn:Disconnect() end) end

 if not result then return nil end

 -- Confirm the egg
 pcall(function()
 Net.fire("Egg.ConfirmEgg", eggName, result.petName, result.size or "")
 end)

 return result
end

---------------------------------------------------------------
-- SELL PET (find pet tool in backpack by species, sell via NPCS.SellPet)
-- Pet tool attributes: "Pet" = species name, "PetId" = unique ID
---------------------------------------------------------------

function Pet._findAndSellPet(petName, Net)
 -- Wait a bit for pet tool to appear in backpack after ConfirmEgg
 task.wait(1)
 local lp = Players.LocalPlayer
 local backpack = lp and lp:FindFirstChild("Backpack")
 if not backpack then return false end

 -- Also check character (might be equipped)
 local char = lp.Character
 local function scanContainer(container)
 if not container then return nil end
 for _, tool in ipairs(container:GetChildren()) do
 if tool:IsA("Tool") then
 local toolPetName = tool:GetAttribute("Pet")
 if toolPetName == petName then
 local petId = tool:GetAttribute("PetId")
 if petId then
 return { tool = tool, petId = petId }
 end
 end
 end
 end
 return nil
 end

 local found = scanContainer(backpack) or scanContainer(char)
 if not found then
 print("[NexHub] Sell: pet tool not found for", petName)
 return false
 end

 -- Equip the tool first (NPC sell requires holding it)
 if char then
 pcall(function() found.tool.Parent = char end)
 task.wait(0.3)
 end

 -- Fire NPCS.SellPet(petId) — invoke for response
 local ok, result = pcall(function()
 return Net.invoke("NPCS.SellPet", found.petId)
 end)

 if ok and result and result.Success then
 print("[NexHub] Sold pet:", petName, "for", tostring(result.SellPrice or "?"))
 return true
 end

 return false
end

---------------------------------------------------------------
-- AUTO HATCH LOOP
---------------------------------------------------------------

function Pet._autoHatch(petConfig, Net, Utils)
 local minRarity = petConfig.MinRarity or "Rare"
 local autoSell = petConfig.AutoSellUnwanted or false

 -- Find egg tools in backpack
 local eggs = Pet._findEggTools()
 if #eggs == 0 then
 Pet._stats.noEggs += 1
 return
 end

 -- Hatch one egg per cycle
 local egg = eggs[1]
 local result = Pet._hatchEgg(egg.eggName, Net)

 if not result then
 Pet._stats.errors += 1
 return
 end

 Pet._stats.hatched += 1
 local speciesRarity = Pet._getSpeciesRarity(result.petName)
 local passes = Pet._passesFilter(result.petName, result.size, minRarity)

 local sizeStr = result.size and (" [" .. result.size .. "]") or ""
 print("[NexHub] Hatched:", result.petName, sizeStr, "(" .. speciesRarity .. ")")

 if passes then
 Pet._stats.kept += 1
 print("[NexHub] KEPT - matches rarity filter:", minRarity .. "+")
 else
 if autoSell then
 local sold = Pet._findAndSellPet(result.petName, Net)
 if sold then
 Pet._stats.sold += 1
 print("[NexHub] SOLD - below rarity filter")
 end
 else
 print("[NexHub] Below filter (" .. minRarity .. "+), kept in inventory")
 end
 end
end

---------------------------------------------------------------
-- START / STOP
---------------------------------------------------------------

function Pet.start(config, Net, Utils)
 if Pet._running then return end
 Pet._running = true

 local interval = config.Timings.PetHatchInterval or 2
 local petConfig = config.Pet or {}

 Pet._thread = task.spawn(function()
 while Pet._running do
 Pet._autoHatch(petConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Auto-Buy Pet started")
end

function Pet.stop()
 Pet._running = false
 for _, conn in ipairs(Pet._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Pet._connections = {}
end

function Pet.getStats()
 return Pet._stats
end

end
---------------------------------------------------------------

Modules.InventoryOptimizer = {}
do
 local M = Modules.InventoryOptimizer
 local Inventory = M
Inventory._running = false
Inventory._thread = nil
Inventory._connections = {}
Inventory._stats = { favorited = 0, promoted = 0, dropped = 0, scanned = 0 }

---------------------------------------------------------------
-- START
---------------------------------------------------------------

function Inventory.start(config, Net, Utils)
 if Inventory._running then return end
 Inventory._running = true

 local interval = config.Timings.InventoryCheckInterval or 10
 local invConfig = config.Inventory or {}

 Inventory._thread = task.spawn(function()
 while Inventory._running do
 Inventory._optimize(invConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Inventory Optimizer started")
end

---------------------------------------------------------------
-- OPTIMIZE LOGIC
---------------------------------------------------------------

function Inventory._optimize(invConfig, Net, Utils)
 Inventory._stats.scanned += 1
 local LP = Utils.getLocalPlayer()
 local backpack = LP and LP:FindFirstChild("Backpack")
 if not backpack then return end

 for _, tool in ipairs(backpack:GetChildren()) do
 if not tool:IsA("Tool") then continue end

 local itemName = tool.Name
 local itemType = tool:GetAttribute("ItemType") or ""
 local fruitName = tool:GetAttribute("FruitName") or ""
 local mutation = tool:GetAttribute("Mutation") or ""
 local size = tool:GetAttribute("Size") or 1

 -- Get base value for this item
 local seedName = fruitName ~= "" and fruitName or itemName
 local baseValue = Inventory._getBaseValue(seedName)
 local mult = Inventory._getMutationMult(mutation, config)
 local estimatedValue = baseValue * (size ^ 2.65) * mult

 -- AUTO-FAVORITE high value fruits
 if invConfig.AutoFavorite ~= false and
 estimatedValue >= (invConfig.FavoriteThreshold or 500) then
 local ok = pcall(function()
 Net.fire("Backpack.SetFruitFavorite", tool.Name, true)
 end)
 if ok then
 Inventory._stats.favorited += 1
 end
 end

 -- AUTO-PROMOTE fruits to inventory
 if invConfig.AutoPromote then
 if itemType == "HarvestedFruit" or
 itemType == "Fruit" or
 fruitName ~= "" then
 local ok = pcall(function()
 Net.fire("Backpack.PromoteFruit", tool.Name)
 end)
 if ok then
 Inventory._stats.promoted += 1
 end
 end
 end

 -- AUTO-DROP low value items
 if invConfig.DropThreshold and
 invConfig.DropThreshold > 0 and
 estimatedValue < invConfig.DropThreshold then
 -- Don't drop seeds or tools
 if itemType ~= "SeedTool" and
 itemType ~= "WateringCan" and
 itemType ~= "Sprinkler" and
 not itemName:match("Seed") then
 local ok = pcall(function()
 Net.fire("DroppedItem.RequestDrop", tool.Name, 1)
 end)
 if ok then
 Inventory._stats.dropped += 1
 end
 end
 end
 end
end

---------------------------------------------------------------
-- VALUE HELPERS
---------------------------------------------------------------

function Inventory._getBaseValue(seedName)
 local values = {
 ["Carrot"] = 5, ["Strawberry"] = 3, ["Blueberry"] = 5,
 ["Tomato"] = 9, ["Apple"] = 12, ["Cactus"] = 40,
 ["Pineapple"] = 30, ["Banana"] = 35, ["Corn"] = 34,
 ["Grape"] = 45, ["Mango"] = 90, ["Coconut"] = 60,
 ["Cherry"] = 350, ["Pomegranate"] = 900,
 ["Dragon Fruit"] = 150, ["Mushroom"] = 13000,
 ["Sunflower"] = 1750, ["Venus Fly Trap"] = 3000,
 ["Moon Bloom"] = 9000, ["Dragon's Breath"] = 3400,
 ["Ghost Pepper"] = 2500, ["Lotus"] = 6500,
 ["Romanesco"] = 1500, ["Poison Apple"] = 900,
 ["Poison Ivy"] = 1700, ["Glow Mushroom"] = 700,
 ["Horned Melon"] = 200, ["Baby Cactus"] = 70,
 ["Tulip"] = 60, ["Bamboo"] = 800, ["Pumpkin"] = 350,
 ["Pinetree"] = 100, ["Green Bean"] = 10,
 ["Beanstalk"] = 2000, ["Thorn Rose"] = 140,
 ["Acorn"] = 200, ["Moon Bloom"] = 9000,
 }
 return values[seedName] or 0
end

function Inventory._getMutationMult(mutation, config)
 if not mutation or mutation == "" then return 1 end
 if config and config.Mutation and config.Mutation.PriceMultipliers then
 return config.Mutation.PriceMultipliers[mutation] or 1
 end
 local defaults = {
 Gold = 20, Rainbow = 50, Electric = 12,
 Frozen = 10, Bloodlit = 5, Chained = 8, Starstruck = 100,
 }
 return defaults[mutation] or 1
end

---------------------------------------------------------------
-- MANUAL OPERATIONS
---------------------------------------------------------------

function Inventory.favoriteAll(Net, Utils, threshold)
 local count = 0
 local backpack = Utils.getLocalPlayer():FindFirstChild("Backpack")
 if not backpack then return 0 end

 for _, tool in ipairs(backpack:GetChildren()) do
 if tool:IsA("Tool") then
 pcall(function()
 Net.fire("Backpack.SetFruitFavorite", tool.Name, true)
 count += 1
 end)
 end
 end
 Inventory._stats.favorited += count
 return count
end

function Inventory.dropAllLowValue(Net, Utils, threshold)
 local count = 0
 local backpack = Utils.getLocalPlayer():FindFirstChild("Backpack")
 if not backpack then return 0 end

 for _, tool in ipairs(backpack:GetChildren()) do
 if tool:IsA("Tool") then
 local fruitName = tool:GetAttribute("FruitName") or tool.Name
 local baseValue = Inventory._getBaseValue(fruitName)
 if baseValue < threshold then
 pcall(function()
 Net.fire("DroppedItem.RequestDrop", tool.Name, 1)
 count += 1
 end)
 end
 end
 end
 Inventory._stats.dropped += count
 return count
end

---------------------------------------------------------------
-- STOP / STATUS
---------------------------------------------------------------

function Inventory.stop()
 Inventory._running = false
 for _, conn in ipairs(Inventory._connections) do
 pcall(function() conn:Disconnect() end)
 end
 Inventory._connections = {}
end

function Inventory.getStats()
 return Inventory._stats
end

end

---------------------------------------------------------------
-- GEAR BUYER MODULE
---------------------------------------------------------------

Modules.GearBuyer = {}
do
 local Gear = Modules.GearBuyer
 Gear._running = false
 Gear._thread = nil
 Gear._stats = { scanned = 0, bought = 0, skipped = 0, errors = 0 }

 -- Cost map from GearShopData
 local GearCosts = {
 ["Trowel"] = 1000,
 ["Common Watering Can"] = 2000,
 ["Speed Mushroom"] = 1500,
 ["Jump Mushroom"] = 1800,
 ["Common Sprinkler"] = 3000,
 ["Sign"] = 4000,
 ["Shrink Mushroom"] = 4500,
 ["Supersize Mushroom"] = 4500,
 ["Uncommon Sprinkler"] = 10000,
 ["Flashbang"] = 8000,
 ["Teleporter"] = 18000,
 ["Rare Sprinkler"] = 50000,
 ["Lantern"] = 12000,
 ["Gnome"] = 50000,
 ["Legendary Sprinkler"] = 100000,
 ["Basic Pot"] = 60000,
 ["Super Sprinkler"] = 300000,
 ["Super Watering Can"] = 250000,
 ["Wheelbarrow"] = 500000,
 }

 function Gear._getGearStockFolder()
 local ok, folder = pcall(function()
 return game:GetService("ReplicatedStorage")
 :WaitForChild("StockValues", 5)
 :WaitForChild("GearShop", 5)
 :WaitForChild("Items", 5)
 end)
 return ok and folder or nil
 end

 function Gear._getStock(gearName)
 local folder = Gear._getGearStockFolder()
 if not folder then return -1 end
 local val = folder:FindFirstChild(gearName)
 if not val then return 0 end
 if val:IsA("ValueBase") then return (val.Value or 0) end
 return 0
 end

 function Gear._buyGear(Net, gearName)
 local ok, err = pcall(function()
 Net.fire("GearShop.PurchaseGear", gearName)
 end)
 if ok then
 return true, 0
 end
 Gear._stats.errors += 1
 return false, 0
 end

 function Gear._pollAndBuy(gearConfig, Net, Utils)
 Gear._stats.scanned += 1

 local targets = gearConfig.TargetGears or {}
 if #targets == 0 then return end

 for _, gearName in ipairs(targets) do
 if not Gear._running then break end

 local stock = Gear._getStock(gearName)
 if stock == 0 then
 Gear._stats.skipped += 1
 continue
 end

 local cost = GearCosts[gearName] or 0
 local sheckles = Utils.getSheckles()
 if cost > 0 and sheckles < cost then
 continue -- can't afford
 end

 local buyCount = 0
 local maxBuys = (stock > 0 and stock) or 10
 for i = 1, maxBuys do
 if not Gear._running then break end

 -- Re-check affordability inside loop
 if cost > 0 and Utils.getSheckles() < cost then break end

 local ok, price = Gear._buyGear(Net, gearName)
 if ok then
 buyCount += 1
 Gear._stats.bought += 1
 task.wait(0.05)
 else
 break
 end
 end

 if buyCount > 0 then
 print("[NexHub] Gear bought:", gearName, "x" .. buyCount)
 end
 end
 end

 function Gear.start(config, Net, Utils)
 if Gear._running then return end
 Gear._running = true

 local gearConfig = config.Gear or {}
 local interval = gearConfig.PollInterval or 30

 Gear._thread = task.spawn(function()
 while Gear._running do
 Gear._pollAndBuy(gearConfig, Net, Utils)
 task.wait(interval)
 end
 end)

 print("[NexHub] Gear Buyer started")
 end

 function Gear.stop()
 Gear._running = false
 end

 function Gear.getStats()
 return Gear._stats
 end
end
---------------------------------------------------------------
-- STATUS
---------------------------------------------------------------

local function getFullStatus()
 local lines = {"NexHub STATUS", "Sheckles: " .. Utils.formatNumber(Utils.getSheckles()), ""}
 for name, mod in pairs(Modules) do
 local st = Running[name] and "ON" or "OFF"
 local info = ""
 if name == "RestockSniper" then
 local t = Config.Restock.TargetSeeds or {}
 info = #t > 0 and table.concat(t, ", ") or "(none)"
 elseif name == "GearBuyer" then
 local t = Config.Gear.TargetGears or {}
 info = #t > 0 and table.concat(t, ", ") or "(none)"
 elseif name == "AutoPlant" then
 info = Config.Plant.PreferSeed or "(auto)"
 elseif name == "AutoBuyPet" then
 info = "min: " .. (Config.Pet.MinRarity or "Rare")
 elseif name == "MutationTracker" then
 info = "min: " .. (Config.Mutation.MinRarity or "Common")
 elseif name == "AutoSell" then
 info = Config.Sell.AutoSell and "auto" or "manual"
 elseif name == "AutoWater" then
 info = Config.Water.WaterAll and "all" or "dry only"
 elseif name == "StealBot" then
 info = Config.Steal.Enabled and "night mode" or "off"
 end
 lines[#lines+1] = " " .. st .. " " .. name .. ": " .. info
 end
 return table.concat(lines, "\n")
end

---------------------------------------------------------------
-- LIVE STATS TRACKER
---------------------------------------------------------------

local Stats = {
 startSheckles = 0,
 startTime = os.clock(),
 sessionHarvested = 0,
 sessionPlanted = 0,
 sessionSold = 0,
 sessionBought = 0,
}

-- Capture initial state on load
function Stats.init()
 Stats.startSheckles = Utils.getSheckles()
 Stats.startTime = os.clock()
end

-- Get elapsed time since start
function Stats.getElapsed()
 return os.clock() - Stats.startTime
end

-- Calculate profit/loss since start
function Stats.getProfit()
 return Utils.getSheckles() - Stats.startSheckles
end

-- Count plants in my garden
function Stats.getPlantCount()
 local garden = Utils.getMyGarden()
 if not garden then return 0 end
 local plants = garden:FindFirstChild("Plants")
 return plants and #plants:GetChildren() or 0
end

-- Calculate approximate garden value (all fruits on all plants)
-- Uses SellValueData * size^2.65 as base estimate
function Stats.getGardenValue()
 local garden = Utils.getMyGarden()
 if not garden then return 0 end
 local total = 0
 local plants = garden:FindFirstChild("Plants")
 if not plants then return 0 end
 for _, plantModel in ipairs(plants:GetChildren()) do
 local seedName = plantModel:GetAttribute("SeedName")
 if not seedName then continue end
 local fruitsFolder = plantModel:FindFirstChild("Fruits")
 if fruitsFolder then
 for _, fruitModel in ipairs(fruitsFolder:GetChildren()) do
 local size = fruitModel:GetAttribute("SizeMultiplier") or 1
 local mutation = fruitModel:GetAttribute("Mutation")
 local baseVal = Stats._sellData[seedName] or 0
 local sizeMult = size ^ 2.65
 local mutMult = 1
 if mutation and Stats._mutData and Stats._mutData[mutation] then
 mutMult = Stats._mutData[mutation].PriceMultiplier or 1
 end
 total += math.floor(baseVal * sizeMult * mutMult)
 end
 else
 -- Single-harvest: plant itself has value
 local size = plantModel:GetAttribute("SizeMultiplier") or 1
 local baseVal = Stats._sellData[seedName] or 0
 total += math.floor(baseVal * (size ^ 2.65))
 end
 end
 return total
end

-- Count backpack items and estimate seed value
function Stats.getBackpackInfo()
 local lp = Players and Players.LocalPlayer
 local bp = lp and lp:FindFirstChild("Backpack")
 if not bp then return 0, 0, 0 end
 local totalItems = 0
 local seedCount = 0
 local fruitCount = 0
 for _, tool in ipairs(bp:GetChildren()) do
 if tool:IsA("Tool") then
 totalItems += 1
 if tool:GetAttribute("SeedTool") then
 seedCount += 1
 elseif tool:GetAttribute("FruitName") or tool:GetAttribute("IsFruit") then
 fruitCount += 1
 end
 end
 end
 return totalItems, seedCount, fruitCount
end

-- Count active modules
function Stats.getActiveModules()
 local count = 0
 local names = {}
 for name, active in pairs(Running) do
 if active then
 count += 1
 table.insert(names, name)
 end
 end
 return count, names
end

-- Build full live stats text for Status tab
function Stats.buildText()
 local sheckles = Utils.getSheckles()
 local profit = Stats.getProfit()
 local elapsed = Stats.getElapsed()
 local gardenVal = Stats.getGardenValue()
 local plantCount = Stats.getPlantCount()
 local totalItems, seedCount, fruitCount = Stats.getBackpackInfo()
 local activeCount, activeNames = Stats.getActiveModules()

 local profitSign = profit >= 0 and "+" or ""
 local profitColor = profit >= 0 and "" or ""

 local lines = {}

 -- Money section
 table.insert(lines, "Money")
 table.insert(lines, string.format(" Current: %s", Utils.formatNumber(sheckles)))
 table.insert(lines, string.format(" Start: %s", Utils.formatNumber(Stats.startSheckles)))
 table.insert(lines, string.format(" Profit: %s%s%s", profitColor, profitSign, Utils.formatNumber(profit)))
 table.insert(lines, "")

 -- Session
 table.insert(lines, "Session")
 table.insert(lines, string.format(" Runtime: %s", Utils.formatTime(elapsed)))
 table.insert(lines, "")

 -- Garden
 table.insert(lines, "Garden")
 table.insert(lines, string.format(" Plants: %d", plantCount))
 table.insert(lines, string.format(" Value: %s", Utils.formatNumber(gardenVal)))
 table.insert(lines, "")

 -- Backpack
 table.insert(lines, "Backpack")
 table.insert(lines, string.format(" Items: %d (Seeds: %d, Fruits: %d)", totalItems, seedCount, fruitCount))
 table.insert(lines, "")

 -- Module configs
 table.insert(lines, string.format("Modules (%d active)", activeCount))
 for name, mod in pairs(Modules) do
 local st = Running[name] and "" or ""
 local info = ""
 if name == "RestockSniper" then
 local t = Config.Restock.TargetSeeds or {}
 info = #t > 0 and table.concat(t, ", ") or "(none)"
 elseif name == "GearBuyer" then
 local t = Config.Gear.TargetGears or {}
 info = #t > 0 and table.concat(t, ", ") or "(none)"
 elseif name == "AutoPlant" then
 info = Config.Plant.PreferSeed or "(auto)"
 elseif name == "AutoBuyPet" then
 info = "min: " .. (Config.Pet.MinRarity or "Rare")
 elseif name == "MutationTracker" then
 info = "min: " .. (Config.Mutation.MinRarity or "Common")
 elseif name == "AutoSell" then
 info = Config.Sell.AutoSell and "auto" or "manual"
 elseif name == "AutoWater" then
 info = Config.Water.WaterAll and "all" or "dry only"
 elseif name == "StealBot" then
 info = Config.Steal.Enabled and "night mode" or "off"
 end
 table.insert(lines, string.format(" %s %s: %s", st, name, info))
 end

 return table.concat(lines, "\n")
end

-- SellValueData cache (loaded lazily)
Stats._sellData = {}
Stats._mutData = {}
task.spawn(function()
 pcall(function()
 local RS = game:GetService("ReplicatedStorage")
 local shared = RS:WaitForChild("SharedModules", 10)
 if shared then
 local svd = shared:WaitForChild("SellValueData", 5)
 if svd then Stats._sellData = require(svd) end
 local md = shared:WaitForChild("MutationData", 5)
 if md then Stats._mutData = require(md) end
 end
 end)
end)

---------------------------------------------------------------
-- RAYFIELD UI
---------------------------------------------------------------

local AllSeeds = {
 -- Sorted by SellValue: low → high
 "Strawberry","Carrot","Blueberry","Tomato","Green Bean",
 "Apple","Pineapple","Corn","Banana","Cactus","Grape",
 "Coconut","Tulip","Baby Cactus","Mango","Pinetree",
 "Thorn Rose","Dragon Fruit","Acorn","Horned Melon",
 "Pumpkin","Cherry","Glow Mushroom","Bamboo",
 "Pomegranate","Poison Apple","Romanesco","Poison Ivy",
 "Sunflower","Beanstalk","Ghost Pepper","Venus Fly Trap",
 "Dragon's Breath","Lotus","Moon Bloom","Mushroom",
}

local AllGears = {
 -- Sorted by Cost: low → high
 "Trowel","Speed Mushroom","Jump Mushroom","Common Watering Can",
 "Common Sprinkler","Sign","Shrink Mushroom","Supersize Mushroom",
 "Flashbang","Uncommon Sprinkler","Lantern","Teleporter",
 "Rare Sprinkler","Gnome","Basic Pot","Legendary Sprinkler",
 "Super Watering Can","Super Sprinkler","Wheelbarrow",
}

local function createUI()
 local ModernV2 = nil
 local ok = pcall(function()
 ModernV2 = loadstring(game:HttpGet("https://raw.githubusercontent.com/nexiuse/NexHubNewUI/refs/heads/main/MainV2.lua"))()
 end)
 if not ok or not ModernV2 then warn("[NexHub] ModernV2 failed") return false end

 -- Init live stats tracker (capture starting money)
 Stats.init()

 -- Helper to convert multi-select dropdown dictionary to array
 local function dictToArray(dict)
 local arr = {}
 for k, v in pairs(dict) do
 if v then
 table.insert(arr, k)
 end
 end
 return arr
 end

 -- Register and apply a custom theme.
 ModernV2:AddTheme({
 Name = "NexHub Purple",
 Accent = Color3.fromRGB(148, 0, 211),
 Background = Color3.fromRGB(8, 8, 13),
 Surface = Color3.fromRGB(20, 22, 27),
 Outline = Color3.fromRGB(45, 48, 58),
 Text = Color3.fromRGB(255, 255, 255),
 Placeholder = Color3.fromRGB(140, 140, 155),
 Button = Color3.fromRGB(148, 0, 211),
 Icon = Color3.fromRGB(255, 255, 255),
 })

 -- Create the floating menu icon.
 local MenuIcon = ModernV2:CreateMenuIcon({
 Image = "rbxassetid://82006436469351",
 Size = 48,
 IconColor = Color3.fromRGB(255, 255, 255),
 BGColor = Color3.fromRGB(20, 22, 27),
 StrokeColor = Color3.fromRGB(148, 0, 211),
 StrokeThick = 1.5,
 Draggable = true,
 })

 -- Create the main window.
 local Window = ModernV2:Window({
 Title = "NexHub",
 Content = "Grow A Garden v" .. VERSION,
 Image = "82006436469351",
 Color = Color3.fromRGB(148, 0, 211),
 Uitransparent = 0.15,
 ShowUser = true,
 Search = true,
 ConfigEnabled = true,
 NotifyOnCallbackError = false,
 Loadingscreen = false,
 Enable3DRenderer = false,
 Keybind = "RightControl",
 Size = UDim2.fromOffset(540, 340),
 Config = {
 ConfigFolder = "NexHub_GaG2",
 AutoSaveFile = "config",
 AutoSave = true,
 AutoLoad = true,
 Overwrite = true,
 Format = "JSON",
 ShowAutoSaveToggle = true,
 TextGradient = true,
 },
 })

 Window:AttachMenuIcon(MenuIcon)

 -- Account area in the lower-left.
 Window:SetAccount({
 Username = game:GetService("Players").LocalPlayer.DisplayName,
 Profile = ModernV2.UserProfile,
 Expires = "Never",
 })

 -- Pembuatan Home Tab / Dashboard
 Window:CreateHomeTab({
 Name = "Dashboard",
 Icon = "lucide:layout-dashboard",
 Content = "NexHub Grow A Garden Script",
 DiscordInvite = "https://discord.gg/UgtRrcjxh3",
 SupportedExecutors = {"Delta","Synapse X","Krnl","Codex","Arceus X"},
 UnsupportedExecutors = {"Roblox Studio"},
 Segments = {
 Details = { Text = "Details", Icon = "lucide:grid-2x2" },
 Script = { Text = "Script Logs", Icon = "lucide:code", Show = true },
 UI = { Text = "UI Logs", Icon = "lucide:file-text", Show = true },
 },
 Changelog = {
 {Title = "Grow A Garden v" .. VERSION, Date = "v" .. VERSION, Description = "Premium Automation Features."},
 },
 UIChangelog = {
 {Title = "UI ModernV2", Date = "Latest", Description = "Tampilan UI Baru premium dengan warna ungu NexHub."},
 },
 })

 _G.GAGHubWindow = Window

 -------------------------------------------------------
 -- TAB 1: FARMING (harvest + sell + water + plant)
 -------------------------------------------------------
 local FarmTab = Window:AddTab({
 Name = "Farming",
 Icon = "lucide:leaf",
 Type = "Single",
 })

 local FarmTabbox = FarmTab:AddTabbox({
     Name = "Farming",
     Position = "center",
 })

 local FarmMain = FarmTabbox:AddTab("Main", "lucide:toggle-right")

 for _, e in ipairs({
     {"Auto Harvest", "AutoHarvest"},
     {"Auto Sell",    "AutoSell"},
     {"Auto Water",   "AutoWater"},
     {"Auto Plant",   "AutoPlant"},
 }) do
     FarmMain:AddToggle({
         Name = e[1],
         Default = false,
         Flag = e[2],
         Callback = function(v) if v then startModule(e[2]) else stopModule(e[2]) end end
     })
 end

 local FarmIntervals = FarmTabbox:AddTab("Intervals", "lucide:timer")

 FarmIntervals:AddSlider({
     Name = "Harvest",
     Min = 0.5, Max = 10, Rounding = 1, Type = "s",
     Default = Config.Timings.HarvestInterval,
     Flag = "HarvestInterval",
     Callback = function(v) Config.Timings.HarvestInterval = v end
 })
 FarmIntervals:AddSlider({
     Name = "Sell",
     Min = 1, Max = 30, Rounding = 0, Type = "s",
     Default = Config.Timings.SellInterval,
     Flag = "SellInterval",
     Callback = function(v) Config.Timings.SellInterval = v end
 })
 FarmIntervals:AddSlider({
     Name = "Water",
     Min = 1, Max = 15, Rounding = 0, Type = "s",
     Default = Config.Timings.WaterInterval,
     Flag = "WaterInterval",
     Callback = function(v) Config.Timings.WaterInterval = v end
 })
 FarmIntervals:AddSlider({
     Name = "Plant",
     Min = 1, Max = 15, Rounding = 0, Type = "s",
     Default = Config.Timings.PlantInterval,
     Flag = "PlantInterval",
     Callback = function(v) Config.Timings.PlantInterval = v end
 })

 local PlantConfigSection = FarmTabbox:AddTab("Plant Config", "lucide:sprout")

 PlantConfigSection:AddSlider({
 Name = "Grid Spacing",
 Min = 2,
 Max = 8,
 Rounding = 1,
 Type = " studs",
 Default = Config.Plant.GridSpacing,
 Flag = "GridSpacing",
 Callback = function(v) Config.Plant.GridSpacing = v end
 })

 PlantConfigSection:AddTextInput({
 Name = "Prefer Seed (empty=any)",
 Placeholder = "e.g. Carrot",
 Numeric = false,
 Flag = "PreferSeed",
 Callback = function(v) Config.Plant.PreferSeed = (v ~= "" and v or nil) end
 })

 -------------------------------------------------------
 -- TAB 2: SHOP & PETS (restock + inventory + pets)
 -------------------------------------------------------
 local ShopTab = Window:AddTab({
 Name = "Shop",
 Icon = "lucide:shopping-cart",
 Type = "Single",
 })

 local ShopTabbox = ShopTab:AddTabbox({
     Name = "Shop",
     Position = "center",
 })
 local ShopLeft = ShopTabbox:AddTab("Restock Sniper", "lucide:shopping-cart")

 ShopLeft:AddToggle({
 Name = "Enabled",
 Default = false,
 Flag = "RestockSniper",
 Callback = function(v) if v then startModule("RestockSniper") else stopModule("RestockSniper") end end
 })

 ShopLeft:AddSlider({
 Name = "Poll",
 Min = 0.5,
 Max = 5,
 Rounding = 1,
 Type = "s",
 Default = Config.Timings.RestockPollInterval,
 Flag = "RestockPollInterval",
 Callback = function(v) Config.Timings.RestockPollInterval = v end
 })

 ShopLeft:AddDropdown({
 Name = "Buy Targets",
 Default = Config.Restock.TargetSeeds,
 Values = AllSeeds,
 Multi = true,
 Search = true,
 Flag = "RestockTargets",
 Callback = function(opts) Config.Restock.TargetSeeds = dictToArray(opts) end
 })

 ShopLeft:AddDropdown({
 Name = "Blacklist",
 Default = Config.Restock.BlacklistedSeeds,
 Values = AllSeeds,
 Multi = true,
 Search = true,
 Flag = "RestockBlacklist",
 Callback = function(opts) Config.Restock.BlacklistedSeeds = dictToArray(opts) end
 })

 local GearSection = ShopTabbox:AddTab("Auto Buy Gear", "lucide:package")

 GearSection:AddToggle({
 Name = "Enabled",
 Default = false,
 Flag = "GearBuyer",
 Callback = function(v) if v then startModule("GearBuyer") else stopModule("GearBuyer") end end
 })

 GearSection:AddSlider({
 Name = "Poll Interval",
 Min = 10,
 Max = 120,
 Rounding = 0,
 Type = "s",
 Default = 30,
 Flag = "GearPollInterval",
 Callback = function(v) Config.Gear.PollInterval = v end
 })

 GearSection:AddDropdown({
 Name = "Buy Gears",
 Default = Config.Gear.TargetGears,
 Values = AllGears,
 Multi = true,
 Search = true,
 Flag = "GearTargets",
 Callback = function(opts) Config.Gear.TargetGears = dictToArray(opts) end
 })

 local InvSection = ShopTabbox:AddTab("Inventory", "lucide:backpack")

 InvSection:AddToggle({
 Name = "Optimizer",
 Default = false,
 Flag = "InventoryOptimizer",
 Callback = function(v) if v then startModule("InventoryOptimizer") else stopModule("InventoryOptimizer") end end
 })

 InvSection:AddSlider({
 Name = "Check",
 Min = 5,
 Max = 60,
 Rounding = 0,
 Type = "s",
 Default = Config.Timings.InventoryCheckInterval,
 Flag = "InventoryCheckInterval",
 Callback = function(v) Config.Timings.InventoryCheckInterval = v end
 })

 local PetSection = ShopTabbox:AddTab("Pets", "lucide:paw-print")

 PetSection:AddToggle({
 Name = "Auto Hatch",
 Default = false,
 Flag = "AutoBuyPet",
 Callback = function(v) if v then startModule("AutoBuyPet") else stopModule("AutoBuyPet") end end
 })

 PetSection:AddSlider({
 Name = "Hatch",
 Min = 1,
 Max = 10,
 Rounding = 1,
 Type = "s",
 Default = Config.Timings.PetHatchInterval,
 Flag = "PetHatchInterval",
 Callback = function(v) Config.Timings.PetHatchInterval = v end
 })

 PetSection:AddDropdown({
 Name = "Min Rarity",
 Default = Config.Pet.MinRarity,
 Values = {"Common","Uncommon","Rare","Legendary","Mythic","Super"},
 Multi = false,
 Search = true,
 Flag = "PetMinRarity",
 Callback = function(opt) Config.Pet.MinRarity = type(opt) == "table" and opt[1] or opt end
 })

 PetSection:AddToggle({
 Name = "Sell Unwanted",
 Default = Config.Pet.AutoSellUnwanted,
 Flag = "PetAutoSell",
 Callback = function(v) Config.Pet.AutoSellUnwanted = v end
 })

 -------------------------------------------------------
 -- TAB 3: EVENTS (mutations + weather + steal)
 -------------------------------------------------------
 local EventTab = Window:AddTab({
 Name = "Events",
 Icon = "lucide:zap",
 Type = "Single",
 })

 local EventTabbox = EventTab:AddTabbox({
     Name = "Events",
     Position = "center",
 })
 local MutSection = EventTabbox:AddTab("Mutations", "lucide:dna")

 MutSection:AddToggle({
 Name = "Tracker",
 Default = false,
 Flag = "MutationTracker",
 Callback = function(v) if v then startModule("MutationTracker") else stopModule("MutationTracker") end end
 })

 MutSection:AddSlider({
 Name = "Scan",
 Min = 1,
 Max = 10,
 Rounding = 0,
 Type = "s",
 Default = Config.Timings.MutationScanInterval,
 Flag = "MutationScanInterval",
 Callback = function(v) Config.Timings.MutationScanInterval = v end
 })

 local WeatherSection = EventTabbox:AddTab("Weather", "lucide:cloud-sun")

 WeatherSection:AddToggle({
 Name = "Weather Bot",
 Default = false,
 Flag = "WeatherBot",
 Callback = function(v) if v then startModule("WeatherBot") else stopModule("WeatherBot") end end
 })

 WeatherSection:AddSlider({
 Name = "Poll",
 Min = 1,
 Max = 15,
 Rounding = 0,
 Type = "s",
 Default = Config.Timings.WeatherPollInterval,
 Flag = "WeatherPollInterval",
 Callback = function(v) Config.Timings.WeatherPollInterval = v end
 })

 local StealSection = EventTabbox:AddTab("Steal Bot", "lucide:ghost")

 StealSection:AddToggle({
 Name = "Enabled (Night)",
 Default = false,
 Flag = "StealBot",
 Callback = function(v) if v then startModule("StealBot") else stopModule("StealBot") end end
 })

 StealSection:AddSlider({
 Name = "Interval",
 Min = 0.5,
 Max = 5,
 Rounding = 1,
 Type = "s",
 Default = Config.Timings.StealInterval,
 Flag = "StealInterval",
 Callback = function(v) Config.Timings.StealInterval = v end
 })

 StealSection:AddSlider({
 Name = "Max/Night",
 Min = 5,
 Max = 50,
 Rounding = 0,
 Type = "",
 Default = Config.Steal.MaxAttemptsPerNight,
 Flag = "MaxStealAttempts",
 Callback = function(v) Config.Steal.MaxAttemptsPerNight = v end
 })

 StealSection:AddSlider({
 Name = "Min Value",
 Min = 0,
 Max = 10000,
 Rounding = 0,
 Type = " $",
 Default = Config.Steal.MinFruitValue,
 Flag = "MinFruitValue",
 Callback = function(v) Config.Steal.MinFruitValue = v end
 })

 -------------------------------------------------------
 -- TAB 4: LIVE STATUS
 -------------------------------------------------------
 local StatusTab = Window:AddTab({
 Name = "Status",
 Icon = "lucide:activity",
 Type = "Single",
 })

 local StatusTabbox = StatusTab:AddTabbox({
     Name = "Status",
     Position = "center",
 })
 local StatusLeft = StatusTabbox:AddTab("Live Stats", "lucide:activity")

 local StatsParagraph = StatusLeft:AddParagraph({
 Name = "Session Overview",
 Content = "Loading stats..."
 })

 local StatusRight = StatusTabbox:AddTab("Controls", "lucide:settings")

 StatusRight:AddButton({
 Name = "Enable All",
 Callback = function()
 for n in pairs(Modules) do startModule(n) end
 Window:Notify({Title="NexHub",Content="All modules enabled",Duration=3})
 end
 })

 StatusRight:AddButton({
 Name = "Disable All",
 Callback = function()
 for n in pairs(Modules) do stopModule(n) end
 Window:Notify({Title="NexHub",Content="All modules disabled",Duration=3})
 end
 })

 -- Live update loop (every 2 seconds)
 task.spawn(function()
 while true do
 pcall(function()
 StatsParagraph:SetContent(Stats.buildText())
 end)
 task.wait(2)
 end
 end)

 return true
end

---------------------------------------------------------------
-- CONSOLE API
---------------------------------------------------------------

_G.GAGHub = {
 Config = Config, Modules = Modules, Net = Networking, Utils = Utils,
 toggle = function(name) toggleModule(name) print("[NexHub] " .. name .. ": " .. (Running[name] and "ON" or "OFF")) end,
 start = startModule, stop = stopModule,
 status = function() print(getFullStatus()) end,
 enableAll = function() for n in pairs(Modules) do startModule(n) end end,
 disableAll = function() for n in pairs(Modules) do stopModule(n) end end,
 stats = function(name) if Modules[name] and Modules[name].getStats then for k,v in pairs(Modules[name].getStats()) do print(" "..k..": "..tostring(v)) end end end,
}

---------------------------------------------------------------
-- STARTUP
---------------------------------------------------------------

local LP = Utils.getLocalPlayer()

LP.CharacterAdded:Connect(function()
 task.wait(3)
 for name, active in pairs(Running) do
 if active then task.spawn(function() stopModule(name) task.wait(1) startModule(name) end) end
 end
end)

task.spawn(function()
 local VirtualUser = game:GetService("VirtualUser")
 LP.Idled:Connect(function()
 VirtualUser:CaptureController()
 VirtualUser:ClickButton2(Vector2.new())
 end)
end)

task.spawn(createUI)
-- Config.Notify("NexHub Loaded!", "Toggle in UI or use _G.NexHub API.", 5)
print("NexHub loaded! Console: _G.NexHub")
