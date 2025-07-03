--------------------------------------------------------------------
--  ESPSystem.lua   –   by ChatGPT, 2025‑07‑03
--------------------------------------------------------------------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local Camera       = Workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer

--------------------------------------------------------------------
--  PUBLIC CONFIG --------------------------------------------------
--------------------------------------------------------------------
local ESP = {}

ESP.Enabled           = false
ESP.Mode              = "Box3D"       -- "Box", "Corner", "Box3D"
ESP.ColorVisible      = Color3.fromRGB(0,255,0)
ESP.ColorHidden       = Color3.fromRGB(255,0,0)
ESP.Transparency      = 0.7
ESP.Box3DMaterial     = Enum.Material.Neon
ESP.Thickness2D       = 2            -- px
ESP.CornerLength      = 12           -- px  (длина линий в режиме Corner)

--------------------------------------------------------------------
--  INTERNAL STATE -------------------------------------------------
--------------------------------------------------------------------
local drawings   = {}   -- [player] = {Line|Part,...}
local updateConn = nil

--------------------------------------------------------------------
--  HELPERS --------------------------------------------------------
--------------------------------------------------------------------
local function worldToViewportPoint(pos)
    local v, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), onScreen, v.Z
end

local function makeLine(thickness)
    local line = Drawing.new("Line")
    line.Thickness = thickness
    line.Visible   = false
    line.ZIndex    = 1
    return line
end

local function clearPlayer(player)
    local pack = drawings[player]
    if not pack then return end
    for _,obj in ipairs(pack) do
        if typeof(obj) == "Instance" then obj:Destroy()
        else obj:Remove() end
    end
    drawings[player] = nil
end

--------------------------------------------------------------------
--  2‑D BOX / CORNER ----------------------------------------------
--------------------------------------------------------------------
local function ensure2D(player)
    if drawings[player] then return end

    if ESP.Mode == "Box" then                 -- 4 линии
        drawings[player] = { makeLine(ESP.Thickness2D),
                             makeLine(ESP.Thickness2D),
                             makeLine(ESP.Thickness2D),
                             makeLine(ESP.Thickness2D) }
    else                                      -- 8 уголков
        local t = {}
        for _ = 1,8 do table.insert(t, makeLine(ESP.Thickness2D)) end
        drawings[player] = t
    end
end

local function update2D(player, character, hrp, color)
    ensure2D(player)

    -- границы модели
    local cframe      = hrp.CFrame
    local size        = character:GetExtentsSize()
    local corners3D   = {
        cframe * CFrame.new(-size.X/2,  size.Y/2,  0).p,  -- TL
        cframe * CFrame.new( size.X/2,  size.Y/2,  0).p,  -- TR
        cframe * CFrame.new( size.X/2, -size.Y/2,  0).p,  -- BR
        cframe * CFrame.new(-size.X/2, -size.Y/2,  0).p   -- BL
    }

    local corners2D, onScreen = {}, true
    for i,world in ipairs(corners3D) do
        local p2d, vis = worldToViewportPoint(world)
        onScreen = onScreen and vis
        corners2D[i] = p2d
    end
    if not onScreen then
        for _,l in ipairs(drawings[player]) do l.Visible = false end
        return
    end

    local pack = drawings[player]
    for _,l in ipairs(pack) do
        l.Color   = color
        l.Visible = true
    end

    if ESP.Mode == "Box" then
        -- 4 стороны
        pack[1].From = corners2D[1]; pack[1].To = corners2D[2] -- top
        pack[2].From = corners2D[2]; pack[2].To = corners2D[3] -- right
        pack[3].From = corners2D[3]; pack[3].To = corners2D[4] -- bottom
        pack[4].From = corners2D[4]; pack[4].To = corners2D[1] -- left

    else -- Corner
        local len = ESP.CornerLength
        -- Top‑Left
        pack[1].From = corners2D[1]; pack[1].To = corners2D[1] + Vector2.new(len, 0)
        pack[2].From = corners2D[1]; pack[2].To = corners2D[1] + Vector2.new(0, len)
        -- Top‑Right
        pack[3].From = corners2D[2]; pack[3].To = corners2D[2] + Vector2.new(-len, 0)
        pack[4].From = corners2D[2]; pack[4].To = corners2D[2] + Vector2.new(0, len)
        -- Bottom‑Right
        pack[5].From = corners2D[3]; pack[5].To = corners2D[3] + Vector2.new(-len, 0)
        pack[6].From = corners2D[3]; pack[6].To = corners2D[3] + Vector2.new(0,-len)
        -- Bottom‑Left
        pack[7].From = corners2D[4]; pack[7].To = corners2D[4] + Vector2.new(len, 0)
        pack[8].From = corners2D[4]; pack[8].To = corners2D[4] + Vector2.new(0,-len)
    end
end

--------------------------------------------------------------------
--  3‑D BOX --------------------------------------------------------
--------------------------------------------------------------------
local function ensure3D(player)
    if drawings[player] then return end

    local box    = Instance.new("Part")
    box.Name        = "ESPBox3D_"..player.Name
    box.Anchored    = true
    box.CanCollide  = false
    box.CastShadow  = false
    box.Transparency = ESP.Transparency
    box.Material    = ESP.Box3DMaterial
    box.Parent      = Workspace

    local corners = {}
    for i=1,8 do
        local c = Instance.new("Part")
        c.Anchored     = true
        c.CanCollide   = false
        c.CastShadow   = false
        c.Size         = Vector3.new(0.2,0.2,0.2)
        c.Transparency = ESP.Transparency
        c.Material     = ESP.Box3DMaterial
        c.Parent       = box
        table.insert(corners, c)
    end

    drawings[player] = {box = box, corners = corners}
end

local function update3D(player, character, hrp, color)
    ensure3D(player)
    local pack  = drawings[player]
    local box   = pack.box
    local size  = character:GetExtentsSize()

    box.Size       = size + Vector3.new(0.5,0.5,0.5)
    box.CFrame     = hrp.CFrame
    box.BrickColor = BrickColor.new(color)
    box.Transparency = ESP.Transparency
    box.Material     = ESP.Box3DMaterial

    local half = box.Size/2
    local offsets = {
        Vector3.new( half.X,  half.Y,  half.Z),
        Vector3.new( half.X,  half.Y, -half.Z),
        Vector3.new( half.X, -half.Y,  half.Z),
        Vector3.new( half.X, -half.Y, -half.Z),
        Vector3.new(-half.X,  half.Y,  half.Z),
        Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new(-half.X, -half.Y, -half.Z),
    }
    for i,corner in ipairs(pack.corners) do
        corner.CFrame      = box.CFrame * CFrame.new(offsets[i])
        corner.BrickColor  = BrickColor.new(color)
        corner.Transparency = ESP.Transparency
        corner.Material     = ESP.Box3DMaterial
    end
end

--------------------------------------------------------------------
--  MASTER UPDATE LOOP --------------------------------------------
--------------------------------------------------------------------
local function playerVisible(targetCharacter, targetHRP)
    local origin = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not origin then return false end
    origin = origin.Position
    local dir   = (targetHRP.Position - origin)
    local ray   = Workspace:Raycast(origin, dir, RaycastParams.new{
        FilterDescendantsInstances = {LocalPlayer.Character, targetCharacter},
        FilterType = Enum.RaycastFilterType.Exclude
    })
    return not ray
end

local function updateAll()
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local char = plr.Character
            local hrp  = char.HumanoidRootPart
            local alive = char:FindFirstChildOfClass("Humanoid")
                    and char.Humanoid.Health > 0
            if alive then
                local color = playerVisible(char, hrp) and ESP.ColorVisible or ESP.ColorHidden
                if ESP.Mode == "Box3D" then
                    update3D(plr, char, hrp, color)
                else
                    update2D(plr, char, hrp, color)
                end
            else
                clearPlayer(plr)
            end
        else
            clearPlayer(plr)
        end
    end
end

local function start()
    if updateConn then return end
    updateConn = RunService.RenderStepped:Connect(updateAll)
end

local function stop()
    if updateConn then updateConn:Disconnect(); updateConn = nil end
    for plr,_ in pairs(drawings) do clearPlayer(plr) end
end

--------------------------------------------------------------------
--  PUBLIC API -----------------------------------------------------
--------------------------------------------------------------------
function ESP:Toggle(state)
    self.Enabled = (state ~= nil) and state or (not self.Enabled)
    if self.Enabled then start() else stop() end
end

function ESP:SetMode(mode) -- "Box", "Corner", "Box3D"
    assert(mode=="Box" or mode=="Corner" or mode=="Box3D",
           "ESP:SetMode → Mode must be 'Box', 'Corner' or 'Box3D'")
    if self.Mode ~= mode then
        -- очистить старые, чтобы перерисовать новыми примитивами
        for plr,_ in pairs(drawings) do clearPlayer(plr) end
        self.Mode = mode
    end
end

function ESP:SetColors(vis, hid)  self.ColorVisible, self.ColorHidden = vis, hid end
function ESP:SetTransparency(t)   self.Transparency = math.clamp(t,0,1) end
function ESP:SetMaterial(mat)     self.Box3DMaterial = mat end
function ESP:SetThickness(px)     self.Thickness2D   = px end
function ESP:SetCornerLength(px)  self.CornerLength  = px end

--------------------------------------------------------------------
return ESP
