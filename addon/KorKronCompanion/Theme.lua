--[[
  The look: Horde war-table frames around parchment, ink-colored text and Morpheus titles, so every window reads
  like a dispatch from the Kor'kron rather than an addon panel.

  Every asset was checked against the Forever client's atlas list, and each one is still tested at runtime: a
  missing atlas falls back to a plain frame instead of showing a green box.
]]

local _, KKC = ...
local Theme = {}
KKC.Theme = Theme

-- Ink on parchment (quest-text browns), plus a blood red for titles and ambushes.
Theme.INK = "|cff3a210e"
Theme.SOFT = "|cff6e5232"
Theme.BLOOD = "|cff7a1010"
Theme.MEND = "|cff1d5a1d"
Theme.INK_RGB = { 0.23, 0.13, 0.06 }

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

-- Same pieces as Blizzard's BFAMissionHorde layout (the Horde war table), defined here so it doesn't depend on
-- which layout file this client loads.
local HORDE_FRAME = {
    mirrorLayout = true,
    TopLeftCorner = { atlas = "HordeFrame-Corner-TopLeft", x = -6, y = 6 },
    TopRightCorner = { atlas = "HordeFrame-Corner-TopLeft", x = 6, y = 6 },
    BottomLeftCorner = { atlas = "HordeFrame-Corner-TopLeft", x = -6, y = -6 },
    BottomRightCorner = { atlas = "HordeFrame-Corner-TopLeft", x = 6, y = -6 },
    TopEdge = { atlas = "_HordeFrameTile-Top" },
    BottomEdge = { atlas = "_HordeFrameTile-Top" },
    LeftEdge = { atlas = "!HordeFrameTile-Left" },
    RightEdge = { atlas = "!HordeFrameTile-Left" },
}

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

-- Class colors are made for dark backgrounds; darken them so they read on parchment.
function Theme.ClassInk(token)
    local c = token and ((C_ClassColor and KKC.try(C_ClassColor.GetClassColor, token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
    if not (c and c.r) then return Theme.INK end
    local f = 0.58
    return ("|cff%02x%02x%02x"):format(c.r * f * 255, c.g * f * 255, c.b * f * 255)
end

-- Parchment page with a Horde war-table border, a faint emblem and (optionally) the Horde banner header.
-- Returns the header text, or nil without a header.
function Theme.WarFrame(f, title)
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
    if Theme.Atlas(emblem, "HordeEmblem") then emblem:SetAlpha(0.07) else emblem:Hide() end

    local bordered = false
    if NineSliceUtil and NineSliceUtil.ApplyLayout and Theme.HasAtlas("HordeFrame-Corner-TopLeft") then
        local border = CreateFrame("Frame", nil, f)
        border:SetAllPoints()
        border:SetFrameLevel(f:GetFrameLevel() + 5)
        bordered = pcall(NineSliceUtil.ApplyLayout, border, HORDE_FRAME)
    end
    if not bordered and f.SetBackdrop then
        f:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
    end

    if not title then return nil end
    local banner = CreateFrame("Frame", nil, f)
    banner:SetSize(380, 108)
    banner:SetPoint("TOP", 0, 46)
    banner:SetFrameLevel(f:GetFrameLevel() + 6)
    local art = banner:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    local text = banner:CreateFontString(nil, "OVERLAY")
    if Theme.Atlas(art, "HordeFrame-Header") then
        Theme.Font(text, 22, true)
        text:SetPoint("CENTER", 0, 4)
        text:SetTextColor(1, 0.82, 0.45)
    else
        art:Hide()
        Theme.Font(text, 24, true)
        text:SetPoint("TOP", f, "TOP", 0, -20)
        text:SetTextColor(0.48, 0.06, 0.06)
    end
    text:SetText(title)
    return text
end

-- An ornate line between sections (a plain ink line without the atlas).
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

-- A button with an in-character label and a plain explanation in its tooltip.
function Theme.Button(parent, label, width, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end
