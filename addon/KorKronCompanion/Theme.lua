--[[
  The look. Two kinds of surface, both dressed in the player's faction:
    - parchment documents (battle card, copy box, toast): war-table border around a parchment page, ink text;
    - the dark hall (the Hall of the Kor'kron hub, Overlord style): dark parchment-textured panels with faction
      accents, inset boxes and icon buttons.
  Horde: red and iron, Horde war-table border, Horde emblem and banner. Alliance: blue and gold, Alliance border,
  emblem and banner.

  Every asset was checked against the Forever client's atlas list, and each one is still tested at runtime: a
  missing atlas falls back to a plain frame instead of showing a green box.
]]

local _, KKC = ...
local Theme = {}
KKC.Theme = Theme

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

-- The same pieces as Blizzard's BFAMissionHorde / BFAMissionAlliance layouts (the war tables), defined here so they
-- don't depend on which layout file this client loads.
local function warTableLayout(corner, top, left)
    return {
        mirrorLayout = true,
        TopLeftCorner = { atlas = corner, x = -6, y = 6 },
        TopRightCorner = { atlas = corner, x = 6, y = 6 },
        BottomLeftCorner = { atlas = corner, x = -6, y = -6 },
        BottomRightCorner = { atlas = corner, x = 6, y = -6 },
        TopEdge = { atlas = top },
        BottomEdge = { atlas = top },
        LeftEdge = { atlas = left },
        RightEdge = { atlas = left },
    }
end

local FACTIONS = {
    Horde = {
        layout = warTableLayout("HordeFrame-Corner-TopLeft", "_HordeFrameTile-Top", "!HordeFrameTile-Left"),
        corner = "HordeFrame-Corner-TopLeft", header = "HordeFrame-Header", emblem = "HordeEmblem",
        icon = "Interface\\Icons\\INV_BannerPVP_01",
        accent = { 0.75, 0.13, 0.09 },   -- borders, bars, selected buttons
        button = { 0.20, 0.05, 0.04 },   -- button face
        tint = { 0.30, 0.10, 0.07 },     -- the dark hall's wash over parchment
        ink = "|cff7a1010",              -- headings on parchment
        gold = "|cffffcf6e",             -- headings on dark
    },
    Alliance = {
        layout = warTableLayout("AllianceFrameCorner-TopLeft", "_AllianceFrameTile-Top", "!AllianceFrameTile-Left"),
        corner = "AllianceFrameCorner-TopLeft", header = "AllianceFrame-Header", emblem = "AllianceEmblem",
        icon = "Interface\\Icons\\INV_BannerPVP_02",
        accent = { 0.22, 0.45, 0.85 },
        button = { 0.05, 0.09, 0.20 },
        tint = { 0.08, 0.13, 0.28 },
        ink = "|cff17306e",
        gold = "|cfff2dd9a",
    },
}

-- Colors on parchment.
Theme.INK = "|cff3a210e"
Theme.SOFT = "|cff58401f"
Theme.MEND = "|cff1d5a1d"
Theme.INK_RGB = { 0.23, 0.13, 0.06 }
-- Colors on the dark hall.
Theme.LIGHT = "|cffeadfca"
Theme.DIM = "|cffa8987e"
Theme.LIGHT_MEND = "|cff7ddc7d"
Theme.LIGHT_RGB = { 0.92, 0.87, 0.79 }

-- The faction theme. Read late (the player's faction isn't known while the addon loads).
function Theme.F()
    local f = FACTIONS[UnitFactionGroup("player") or ""] or FACTIONS.Horde
    Theme.BLOOD = f.ink -- heading color on parchment (kept under its first name: red for the Horde)
    Theme.GOLD = f.gold
    return f
end
Theme.BLOOD = FACTIONS.Horde.ink
Theme.GOLD = FACTIONS.Horde.gold
KKC.On("PLAYER_LOGIN", function() Theme.F() end)

function Theme.HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and KKC.try(C_Texture.GetAtlasInfo, name) ~= nil
end

-- Sets an atlas when the client has it; returns false otherwise so the caller can fall back.
function Theme.Atlas(tex, name, useSize)
    if not Theme.HasAtlas(name) then return false end
    tex:SetAtlas(name, useSize)
    return true
end

function Theme.Font(fs, size, title)
    if not fs:SetFont(title and TITLE_FONT or BODY_FONT, size, "") then
        fs:SetFontObject(title and "GameFontNormalLarge" or "GameFontHighlight")
    end
    fs:SetShadowOffset(0, 0)
end

local function classColor(token)
    return token and ((C_ClassColor and KKC.try(C_ClassColor.GetClassColor, token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
end

-- Class colors are made for dark backgrounds; darken them so they read on parchment.
function Theme.ClassInk(token)
    local c = classColor(token)
    if not (c and c.r) then return Theme.INK end
    -- 0.58 was too pale in game (Warrior tan and Priest white nearly vanished); 0.42 keeps the hue and reads.
    local f = 0.42
    return ("|cff%02x%02x%02x"):format(c.r * f * 255, c.g * f * 255, c.b * f * 255)
end

-- Class colors as they are, for the dark hall.
function Theme.ClassLight(token)
    local c = classColor(token)
    if not (c and c.r) then return Theme.LIGHT end
    return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function border(f, layout)
    if NineSliceUtil and NineSliceUtil.ApplyLayout and Theme.HasAtlas(layout.TopLeftCorner.atlas) then
        local b = CreateFrame("Frame", nil, f)
        b:SetAllPoints()
        b:SetFrameLevel(f:GetFrameLevel() + 5)
        if pcall(NineSliceUtil.ApplyLayout, b, layout) then return b end
        b:Hide()
    end
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
    end
end

-- The faction banner above a frame, with its title. Returns the banner frame and the title text.
local function banner(f, title, onParchment)
    local F = Theme.F()
    local b = CreateFrame("Frame", nil, f)
    b:SetSize(380, 108)
    b:SetPoint("TOP", 0, 46)
    b:SetFrameLevel(f:GetFrameLevel() + 6)
    local art = b:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    local text = b:CreateFontString(nil, "OVERLAY")
    if Theme.Atlas(art, F.header) then
        Theme.Font(text, 22, true)
        text:SetPoint("CENTER", 0, 4)
        text:SetTextColor(1, 0.85, 0.5)
    else
        art:Hide()
        Theme.Font(text, 24, true)
        text:SetPoint("TOP", f, "TOP", 0, -20)
        if onParchment then text:SetTextColor(0.4, 0.08, 0.06) else text:SetTextColor(1, 0.82, 0.45) end
    end
    text:SetText(title)
    return b, text
end

-- A parchment document: war-table border around a parchment page, faint emblem, optional banner title.
-- Returns the banner title text, or nil without a title.
function Theme.WarFrame(f, title)
    local F = Theme.F()
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 8, -8)
    bg:SetPoint("BOTTOMRIGHT", -8, 8)
    if not Theme.Atlas(bg, "ChromieTime-Parchment") then bg:SetColorTexture(0.84, 0.74, 0.55, 1) end

    -- Darken the page edges a little so it doesn't look flat.
    local shade = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetAllPoints(bg)
    shade:SetColorTexture(0.25, 0.12, 0.04, 0.10)

    local emblem = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    emblem:SetSize(260, 260)
    emblem:SetPoint("CENTER", 0, -10)
    if Theme.Atlas(emblem, F.emblem) then emblem:SetAlpha(0.07) else emblem:Hide() end

    border(f, F.layout)
    if not title then return nil end
    local _, text = banner(f, title, true)
    return text
end

-- The dark hall (Overlord style): parchment texture washed dark in the faction's color, war-table border, banner,
-- a faint emblem. Returns { border, banner, title, emblem } so a docked hall can hide its own frame.
function Theme.DarkFrame(f, title)
    local F = Theme.F()
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 6, -6)
    bg:SetPoint("BOTTOMRIGHT", -6, 6)
    if Theme.Atlas(bg, "ChromieTime-Parchment") then
        bg:SetVertexColor(0.30, 0.24, 0.19) -- parchment grain, darkened
    else
        bg:SetColorTexture(0.10, 0.07, 0.05, 0.97)
    end
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    wash:SetAllPoints(bg)
    wash:SetColorTexture(F.tint[1], F.tint[2], F.tint[3], 0.35)
    local vignette = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    vignette:SetAllPoints(bg)
    vignette:SetColorTexture(0, 0, 0, 0.30)

    local emblem = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    emblem:SetSize(320, 320)
    emblem:SetPoint("CENTER", 90, -20)
    if Theme.Atlas(emblem, F.emblem) then emblem:SetAlpha(0.06) else emblem:Hide() end

    local parts = { emblem = emblem, border = border(f, F.layout) }
    if title then parts.banner, parts.title = banner(f, title, false) end
    return parts
end

-- A dark inset box with a thin border in the faction's accent (the boxes in Overlord's panel).
function Theme.Inset(parent)
    local F = Theme.F()
    local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.03, 0.02, 0.02, 0.55)
        box:SetBackdropBorderColor(F.accent[1] * 0.75, F.accent[2] * 0.75, F.accent[3] * 0.75, 0.9)
    end
    return box
end

-- An ornate line between sections (a plain line without the atlas).
function Theme.Divider(parent, width)
    local t = parent:CreateTexture(nil, "ARTWORK")
    if Theme.Atlas(t, "Campaign-QuestLog-LoreDivider") then
        t:SetSize(width, 30)
    else
        t:SetSize(width, 1)
        t:SetColorTexture(0.35, 0.2, 0.08, 0.6)
    end
    return t
end

-- Text on parchment: body font, ink color.
function Theme.Text(parent, size, justify, title)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 13, title)
    fs:SetTextColor(Theme.INK_RGB[1], Theme.INK_RGB[2], Theme.INK_RGB[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Text on the dark hall: light, or gold for titles.
function Theme.LightText(parent, size, justify, title)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 13, title)
    if title then fs:SetTextColor(1, 0.82, 0.45) else fs:SetTextColor(Theme.LIGHT_RGB[1], Theme.LIGHT_RGB[2], Theme.LIGHT_RGB[3]) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function tooltip(b, label, tip)
    if not tip then return end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label, 1, 0.82, 0)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A red panel button with an in-character label and a plain explanation in its tooltip (parchment documents).
function Theme.Button(parent, label, width, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    tooltip(b, label, tip)
    return b
end

-- A hall button (Overlord style): dark face in the faction's color, accent border, optional icon, gold label.
-- b:SetSelected(true) lights the border for the chosen section or period.
function Theme.HallButton(parent, label, width, height, icon, tip, onClick)
    local F = Theme.F()
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, height or 28)
    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(F.button[1], F.button[2], F.button[3], 0.95)
    end
    local x = 10
    if icon then
        local t = b:CreateTexture(nil, "ARTWORK")
        local size = (height or 28) - 8
        t:SetSize(size, size)
        t:SetPoint("LEFT", 6, 0)
        t:SetTexture(icon)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = t
        x = 12 + size
    end
    local text = Theme.LightText(b, 13, icon and "LEFT" or "CENTER")
    text:SetTextColor(1, 0.82, 0.45)
    if icon then text:SetPoint("LEFT", x, 0) else text:SetPoint("CENTER") end
    text:SetText(label)
    b.label = text
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(F.accent[1], F.accent[2], F.accent[3], 0.25)
    function b:SetSelected(on)
        self.selected = on
        if self.SetBackdropBorderColor then
            if on then self:SetBackdropBorderColor(1, 0.82, 0.4, 1)
            else self:SetBackdropBorderColor(F.accent[1] * 0.8, F.accent[2] * 0.8, F.accent[3] * 0.8, 0.9) end
        end
        if on then self:SetBackdropColor(F.accent[1] * 0.55, F.accent[2] * 0.55, F.accent[3] * 0.55, 0.95)
        else self:SetBackdropColor(F.button[1], F.button[2], F.button[3], 0.95) end
    end
    function b:SetLabel(t) self.label:SetText(t) end
    b:SetSelected(false)
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    hooksecurefunc(b, "SetEnabled", function(self, on) self:SetAlpha(on and 1 or 0.45) end)
    tooltip(b, label, tip)
    return b
end

-- A progress bar in the faction's accent with "37 / 100" on it (War Ledger).
function Theme.Bar(parent, width, height)
    local F = Theme.F()
    local bar = CreateFrame("StatusBar", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bar:SetSize(width, height or 16)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(F.accent[1], F.accent[2], F.accent[3])
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        bar:SetBackdropColor(0, 0, 0, 0.6)
        bar:SetBackdropBorderColor(0.5, 0.4, 0.3, 0.8)
    end
    bar.text = Theme.LightText(bar, 11, "CENTER")
    bar.text:SetPoint("CENTER")
    function bar:SetProgress(value, goal)
        self:SetMinMaxValues(0, math.max(goal, 1))
        self:SetValue(math.min(value, goal))
        self.text:SetText(("%d / %d"):format(value, goal))
    end
    return bar
end
