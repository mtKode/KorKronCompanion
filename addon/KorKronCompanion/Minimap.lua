--[[
  A button on the minimap's edge: left click opens the Hall of the Kor'kron (/kkc), right click the latest battle
  report. Drag it around the edge to move it. /kkc minimap off hides it.

  Named KorKronCompanionMinimapButton and parented to the Minimap, like other addons' buttons, so minimap button
  collectors (MinimapButtonButton and the like) pick it up.
]]

local _, KKC = ...
local Theme = KKC.Theme
local MinimapButton = {}
KKC.MinimapButton = MinimapButton

local button

local function place()
    local angle = math.rad(KKC.settings().minimap.angle or 200)
    local radius = (KKC.try(Minimap.GetWidth, Minimap) or 140) / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- The angle from the minimap's center to the cursor, in degrees.
local function cursorAngle()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function build()
    local b = CreateFrame("Button", "KorKronCompanionMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(Theme.F().icon) -- the faction's war banner
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            SlashCmdList.KORKRONCOMPANION("card")
        else
            KKC.Hub.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            KKC.settings().minimap.angle = cursorAngle()
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Kor'kron Companion", 1, 0.82, 0)
        GameTooltip:AddLine("Left click: the Hall of the Kor'kron", 1, 1, 1)
        GameTooltip:AddLine("Right click: the latest battle report", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function MinimapButton.Refresh()
    if not Minimap then return end
    button = button or build()
    place()
    button:SetShown(not KKC.settings().minimap.hide)
end

KKC.On("PLAYER_LOGIN", function()
    -- The icon follows the faction, which is only known once the character is in the world.
    MinimapButton.Refresh()
    if button then button.icon:SetTexture(Theme.F().icon) end
end)
