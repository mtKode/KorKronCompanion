--[[
  The look, dressed in the player's faction:
    - the book (the Hall of the Kor'kron on its own): a leather cover, two dark pages, light text and gold titles;
    - sheets (the battle card, the scribe window): one dark page of the same book, the same text and buttons;
    - the dark hall (docked in the Legacy window, Overlord style): dark parchment-textured panels with faction
      accents, inset boxes and icon buttons.
  (The toast after a battle is still a small parchment note.)
  Horde: red and iron, Horde war-table border, Horde emblem and banner. Alliance: blue and gold, Alliance border,
  emblem and banner.

  Every asset was checked against the Forever client's atlas list, and each one is still tested at runtime: a
  missing atlas falls back to a plain frame instead of showing a green box.
]]

local ADDON, KKC = ...
local Theme = {}
-- The addon's own art (tools/make_textures.py makes it).
Theme.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
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

-- Colors on parchment: near-black browns (the first, lighter inks were hard to read in game).
Theme.INK = "|cff24130a"
Theme.SOFT = "|cff4a3218"
Theme.MEND = "|cff145214"
Theme.INK_RGB = { 0.14, 0.075, 0.04 }
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

-- flags: "" (plain) or "OUTLINE" (a thin dark edge: makes black text look bold and keeps gold readable on paper).
function Theme.Font(fs, size, title, flags)
    if not fs:SetFont(title and TITLE_FONT or BODY_FONT, size, flags or "") then
        fs:SetFontObject(title and "GameFontNormalLarge" or "GameFontHighlight")
    end
    fs:SetShadowOffset(0, 0)
end

-- A heading on parchment: the title font in the faction's ink (red for the Horde). A bold black outlined version
-- was tried and read worse in game.
function Theme.Heading(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 18, true)
    local r, g, b = Theme.F().ink:match("|cff(%x%x)(%x%x)(%x%x)")
    fs:SetTextColor(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- A title on parchment in the game's own yellow, edged dark so it stands out from the paper.
function Theme.GoldTitle(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 28, true, "OUTLINE")
    fs:SetTextColor(1, 0.82, 0)
    fs:SetJustifyH(justify or "CENTER")
    return fs
end

local function classColor(token)
    return token and ((C_ClassColor and KKC.try(C_ClassColor.GetClassColor, token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
end

-- Class colors are made for dark backgrounds; darken them so they read on parchment. Each is darkened by its own
-- brightness, so pale ones (Priest white, Rogue yellow, Warrior tan) end up as dark as the deep ones: one fixed
-- factor left those nearly invisible in game.
local INK_LUMINANCE = 0.22

function Theme.ClassInk(token)
    local c = classColor(token)
    if not (c and c.r) then return Theme.INK end
    local lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    local f = math.min(1, INK_LUMINANCE / math.max(lum, 0.01))
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

-- The dark hall (Overlord style): parchment texture washed dark in the faction's color, war-table border, banner,
-- a faint emblem. Returns { border, banner, title, emblem } so a docked hall can hide its own frame.
function Theme.DarkFrame(f, title)
    local F = Theme.F()
    -- Solid underneath, so the see-through parts of the parchment art don't show the game world.
    local backing = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    backing:SetPoint("TOPLEFT", 6, -6)
    backing:SetPoint("BOTTOMRIGHT", -6, 6)
    backing:SetColorTexture(0.08, 0.06, 0.05, 1)

    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints(backing)
    if Theme.Atlas(bg, "ChromieTime-Parchment") then
        bg:SetVertexColor(0.30, 0.24, 0.19) -- parchment grain, darkened
    else
        bg:Hide()
    end
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    wash:SetAllPoints(backing)
    wash:SetColorTexture(F.tint[1], F.tint[2], F.tint[3], 0.35)
    local vignette = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    vignette:SetAllPoints(backing)
    vignette:SetColorTexture(0, 0, 0, 0.30)

    local emblem = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    emblem:SetSize(320, 320)
    emblem:SetPoint("CENTER", 90, -20)
    if Theme.Atlas(emblem, F.emblem) then emblem:SetAlpha(0.06) else emblem:Hide() end

    local parts = { emblem = emblem, border = border(f, F.layout), dark = { backing, bg, wash, vignette, emblem } }
    if title then parts.banner, parts.title = banner(f, title, false) end
    return parts
end

-- ------------------------------------------------------------------------------------------------
-- The hall as a book (on its own, not docked): a leather cover inside the iron border, two parchment pages with a
-- shadowed spine between them at `spineX`, page edges along the bottom, and a ribbon bookmark. The client has no
-- open-book art, so it is built from the parchment we know is there. Returns the textures to show or hide.
-- ------------------------------------------------------------------------------------------------

local function gradient(tex, orientation, r, g, b, fromAlpha, toAlpha)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orientation, CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha))
    else
        tex:SetColorTexture(r, g, b, (fromAlpha + toAlpha) / 2)
    end
end

function Theme.BookFrame(f, spineX)
    local F = Theme.F()
    local parts = {}
    local function tex(layer, sub)
        local t = f:CreateTexture(nil, layer, nil, sub)
        parts[#parts + 1] = t
        return t
    end
    local function line(layer, sub, r, g, b, a)
        local t = tex(layer, sub)
        t:SetColorTexture(r, g, b, a)
        return t
    end

    -- Leather cover, a little of the faction's color in it.
    local cover = tex("BACKGROUND", -8)
    cover:SetPoint("TOPLEFT", 6, -6)
    cover:SetPoint("BOTTOMRIGHT", -6, 6)
    cover:SetColorTexture(0.15 + F.tint[1] * 0.15, 0.08 + F.tint[2] * 0.15, 0.04 + F.tint[3] * 0.15, 1)
    local grain = tex("BACKGROUND", -7)
    grain:SetAllPoints(cover)
    if Theme.Atlas(grain, "ChromieTime-Parchment") then grain:SetVertexColor(0.32, 0.20, 0.12); grain:SetAlpha(0.5) else grain:Hide() end

    -- Two separate pages with a gap at the spine where the cover shows through.
    -- The cover's edge: a dark rim with a pressed line just inside it (in place of the iron frame).
    local rim = { { "TOPLEFT", "TOPRIGHT", nil, 4 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 4 },
                  { "TOPLEFT", "BOTTOMLEFT", 4, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 4, nil } }
    for _, e in ipairs(rim) do
        local dark = line("BACKGROUND", -6, 0.05, 0.025, 0.01, 1)
        dark:SetPoint(e[1], cover, e[1])
        dark:SetPoint(e[2], cover, e[2])
        if e[3] then dark:SetWidth(e[3]) else dark:SetHeight(e[4]) end
        local pressed = line("BACKGROUND", -6, 0.55, 0.38, 0.22, 0.35)
        local dx = (e[1]:find("LEFT") and 10 or -10)
        local dy = (e[1]:find("TOP") and -10 or 10)
        pressed:SetPoint(e[1], cover, e[1], e[3] and dx or 10, e[4] and dy or -10)
        pressed:SetPoint(e[2], cover, e[2], e[3] and dx or -10, e[4] and dy or 10)
        if e[3] then pressed:SetWidth(1) else pressed:SetHeight(1) end
    end

    local inset, gap = 26, 9
    local function page(left)
        -- A shadow the page casts on the cover.
        local shadow = line("BACKGROUND", -6, 0, 0, 0, 0.45)
        local under = line("BACKGROUND", -5, 0.16, 0.11, 0.07, 1)
        if left then
            under:SetPoint("TOPLEFT", inset, -inset)
            under:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", spineX - gap, inset)
        else
            under:SetPoint("TOPLEFT", f, "TOPLEFT", spineX + gap, -inset)
            under:SetPoint("BOTTOMRIGHT", -inset, inset)
        end
        shadow:SetPoint("TOPLEFT", under, "TOPLEFT", left and -3 or 3, -4)
        shadow:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", left and -3 or 3, -4)
        local paper = tex("BACKGROUND", -4)
        paper:SetAllPoints(under)
        paper:SetTexture(Theme.MEDIA .. "Page") -- our aged page (Media/Page.tga), darkened: bright text on a dark page
        paper:SetVertexColor(0.30, 0.24, 0.18)

        -- Leaves under the page: edges peeking out along the bottom and the outer side.
        for i = 1, 3 do
            local shade = 0.30 - i * 0.05
            local bottom = line("BACKGROUND", -5, shade, shade * 0.88, shade * 0.66, 1)
            bottom:SetPoint("TOPLEFT", under, "BOTTOMLEFT", left and (i * 2) or 0, 0)
            bottom:SetPoint("TOPRIGHT", under, "BOTTOMRIGHT", left and 0 or -(i * 2), 0)
            bottom:SetHeight(i * 2)
            local side = line("BACKGROUND", -5, shade, shade * 0.88, shade * 0.66, 1)
            if left then
                side:SetPoint("TOPRIGHT", under, "TOPLEFT", 0, -(i * 2))
                side:SetPoint("BOTTOMRIGHT", under, "BOTTOMLEFT", 0, 0)
            else
                side:SetPoint("TOPLEFT", under, "TOPRIGHT", 0, -(i * 2))
                side:SetPoint("BOTTOMLEFT", under, "BOTTOMRIGHT", 0, 0)
            end
            side:SetWidth(i * 2)
        end

        -- The page curls down into the fold (a deep shadow) and darkens a little at its outer edge.
        local fold = tex("BORDER", 1)
        fold:SetWidth(70)
        local outer = tex("BORDER", 1)
        outer:SetWidth(26)
        if left then
            fold:SetPoint("TOPRIGHT", under, "TOPRIGHT")
            fold:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT")
            gradient(fold, "HORIZONTAL", 0, 0, 0, 0, 0.55)
            outer:SetPoint("TOPLEFT", under, "TOPLEFT")
            outer:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT")
            gradient(outer, "HORIZONTAL", 0.25, 0.13, 0.05, 0.12, 0)
        else
            fold:SetPoint("TOPLEFT", under, "TOPLEFT")
            fold:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT")
            gradient(fold, "HORIZONTAL", 0, 0, 0, 0.55, 0)
            outer:SetPoint("TOPRIGHT", under, "TOPRIGHT")
            outer:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT")
            gradient(outer, "HORIZONTAL", 0.25, 0.13, 0.05, 0, 0.12)
        end
        -- A thin outline, so each page reads as its own sheet.
        local edges = {
            { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
            { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
        }
        for _, e in ipairs(edges) do
            local t = line("BORDER", 2, 0.55, 0.44, 0.28, 0.45)
            t:SetPoint(e[1], under, e[1])
            t:SetPoint(e[2], under, e[2])
            if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        end
        return under
    end
    page(true)
    local right = page(false)

    -- The binding between the pages: a band of the cover's leather, darker in the middle, with its stitching.
    local spine = line("BACKGROUND", -6, 0.07, 0.035, 0.015, 1)
    spine:SetPoint("TOP", f, "TOPLEFT", spineX, -inset + 6)
    spine:SetPoint("BOTTOM", f, "BOTTOMLEFT", spineX, inset - 8)
    spine:SetWidth(gap * 2)
    for _, dx in ipairs({ -4, 4 }) do
        local ridge = line("BACKGROUND", -5, 0.42, 0.27, 0.14, 0.45)
        ridge:SetPoint("TOP", spine, "TOP", dx, -6)
        ridge:SetPoint("BOTTOM", spine, "BOTTOM", dx, 6)
        ridge:SetWidth(1)
    end

    -- Brass caps on the cover's corners.
    for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local point, sx, sy = corner[1], corner[2], corner[3]
        for _, piece in ipairs({ { 30, 7 }, { 7, 30 } }) do
            local brass = line("ARTWORK", 1, 0.66, 0.50, 0.24, 1)
            brass:SetSize(piece[1], piece[2])
            brass:SetPoint(point, cover, point, 0, 0)
            local shine = line("ARTWORK", 2, 0.86, 0.71, 0.40, 0.8)
            shine:SetSize(piece[1] > piece[2] and piece[1] - 4 or 1, piece[2] > piece[1] and piece[2] - 4 or 1)
            shine:SetPoint(point, cover, point, sx * 2, sy * 2)
        end
        local rivet = line("ARTWORK", 3, 0.30, 0.20, 0.08, 1)
        rivet:SetSize(3, 3)
        rivet:SetPoint(point, cover, point, sx * 2, sy * 2)
    end

    -- The faction emblem faintly printed on the right page.
    local emblem = tex("BORDER", 0)
    emblem:SetSize(300, 300)
    emblem:SetPoint("CENTER", right, "CENTER", 0, -10)
    if Theme.Atlas(emblem, F.emblem) then emblem:SetAlpha(0.06) else emblem:Hide() end
    return parts
end

-- One dark page in a leather cover, like a sheet from the hall's book: the battle card and the scribe window.
-- The title sits on the page in gold (no banner). Returns the title text, or nil without a title.
function Theme.SheetFrame(f, title)
    local F = Theme.F()
    local function line(layer, sub, r, g, b, a)
        local t = f:CreateTexture(nil, layer, nil, sub)
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local cover = line("BACKGROUND", -8, 0.15 + F.tint[1] * 0.15, 0.08 + F.tint[2] * 0.15, 0.04 + F.tint[3] * 0.15, 1)
    cover:SetPoint("TOPLEFT", 6, -6)
    cover:SetPoint("BOTTOMRIGHT", -6, 6)
    local grain = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    grain:SetAllPoints(cover)
    if Theme.Atlas(grain, "ChromieTime-Parchment") then grain:SetVertexColor(0.32, 0.20, 0.12); grain:SetAlpha(0.5) else grain:Hide() end
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 4 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 4 },
                         { "TOPLEFT", "BOTTOMLEFT", 4, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 4, nil } }) do
        local dark = line("BACKGROUND", -6, 0.05, 0.025, 0.01, 1)
        dark:SetPoint(e[1], cover, e[1])
        dark:SetPoint(e[2], cover, e[2])
        if e[3] then dark:SetWidth(e[3]) else dark:SetHeight(e[4]) end
    end

    -- The page: our aged texture (Media/Page.tga) darkened, a shadow under it, darker towards the sides.
    local inset = 16
    local shadow = line("BACKGROUND", -6, 0, 0, 0, 0.45)
    local under = line("BACKGROUND", -5, 0.16, 0.11, 0.07, 1)
    under:SetPoint("TOPLEFT", inset, -inset)
    under:SetPoint("BOTTOMRIGHT", -inset, inset)
    shadow:SetPoint("TOPLEFT", under, "TOPLEFT", 3, -4)
    shadow:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", 3, -4)
    local paper = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    paper:SetAllPoints(under)
    paper:SetTexture(Theme.MEDIA .. "Page")
    paper:SetVertexColor(0.30, 0.24, 0.18)
    for _, left in ipairs({ true, false }) do
        local edge = f:CreateTexture(nil, "BORDER", nil, 1)
        edge:SetWidth(60)
        edge:SetPoint(left and "TOPLEFT" or "TOPRIGHT", under)
        edge:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", under)
        gradient(edge, "HORIZONTAL", 0, 0, 0, left and 0.35 or 0, left and 0 or 0.35)
    end
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = line("BORDER", 2, 0.55, 0.44, 0.28, 0.45)
        t:SetPoint(e[1], under, e[1])
        t:SetPoint(e[2], under, e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
    end
    -- Brass caps on the corners, as on the book.
    for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local point, sx, sy = corner[1], corner[2], corner[3]
        for _, piece in ipairs({ { 26, 6 }, { 6, 26 } }) do
            local brass = line("ARTWORK", 1, 0.66, 0.50, 0.24, 1)
            brass:SetSize(piece[1], piece[2])
            brass:SetPoint(point, cover, point, 0, 0)
            local shine = line("ARTWORK", 2, 0.86, 0.71, 0.40, 0.8)
            shine:SetSize(piece[1] > piece[2] and piece[1] - 4 or 1, piece[2] > piece[1] and piece[2] - 4 or 1)
            shine:SetPoint(point, cover, point, sx * 2, sy * 2)
        end
    end
    local emblem = f:CreateTexture(nil, "BORDER", nil, 0)
    emblem:SetSize(300, 300)
    emblem:SetPoint("CENTER", 0, -10)
    if Theme.Atlas(emblem, F.emblem) then emblem:SetAlpha(0.05) else emblem:Hide() end
    if not title then return nil end
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", 0, -30)
    Theme.BookTitle(text, 24)
    text:SetText(title)
    return text
end

-- Light text for the sheets (the battle card, the scribe window): always light, whatever the hall shows.
function Theme.SheetText(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 13)
    fs:SetTextColor(0.92, 0.87, 0.79)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- A gold title for the sheets.
function Theme.SheetTitle(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.BookTitle(fs, size or 18)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- A dark panel with a thin tan border, as on the book's pages (for the sheets; the hall doesn't recolor it).
function Theme.SheetPanel(parent)
    local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.04, 0.025, 0.015, 0.55)
        box:SetBackdropBorderColor(0.55, 0.44, 0.28, 0.55)
    end
    return box
end

-- ------------------------------------------------------------------------------------------------
-- Hall ink: the hall's text and boxes are light on the dark hall and ink on the book's pages. Theme.SetBook(on)
-- switches the colors the hall builds its text from (Theme.LIGHT, DIM, LIGHT_MEND, HALL_GOLD) and recolors every
-- hall text and box already made; the hall then refreshes to rebuild its strings.
-- ------------------------------------------------------------------------------------------------

local DARK = { LIGHT = "|cffeadfca", DIM = "|cffa8987e", LIGHT_MEND = "|cff7ddc7d", rgb = { 0.92, 0.87, 0.79 } }
local DARK_RGB = DARK.rgb
-- Book ink: near-black, and the dim text only a little lighter (a pale brown was hard to read on the grain).
-- The book is dark too now (bright text on dark pages read better than ink on light paper): the same light colors,
-- the secondary text a touch warmer.
local BOOK = { LIGHT = "|cffeadfca", DIM = "|cffb3a183", LIGHT_MEND = "|cff7ddc7d", rgb = { 0.92, 0.87, 0.79 } }
Theme.book = false
Theme.HALL_GOLD = "|cffffd100"
Theme.AMBER = "|cff6e4100" -- labels inside text on the book's pages
-- Color codes for text on dark pages: good news, bad news, places, and the enemy (in their faction's color).
Theme.GOOD = "|cff7ee05e"
Theme.BAD = "|cffff6f5a"
Theme.PLACE = "|cff8fc6ff"
function Theme.Foe() return UnitFactionGroup("player") == "Alliance" and "|cffff5a4d" or "|cff5aa2ff" end
local hallTexts = setmetatable({}, { __mode = "k" }) -- fontstring -> true for titles
local hallBoxes = setmetatable({}, { __mode = "k" })

-- A title on the book's dark page: the game's yellow on a black drop shadow (an outline smeared the title font).
function Theme.BookTitle(fs, size)
    Theme.Font(fs, size, true)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end

local function colorText(fs, title)
    if title then
        if Theme.book then
            Theme.BookTitle(fs, fs.kkSize or 15)
        else
            Theme.Font(fs, fs.kkSize or 15, true)
            fs:SetTextColor(1, 0.82, 0.45)
        end
    else
        local c = Theme.LIGHT_RGB
        fs:SetTextColor(c[1], c[2], c[3])
    end
end

local function colorBox(box)
    for _, rule in ipairs(box.rules or {}) do rule:Hide() end -- dividers suited the light page; the dark one has panels
    if not box.SetBackdropColor then return end
    local F = Theme.F()
    if Theme.book then
        -- A dark panel with a thin tan border on the dark page.
        box:SetBackdropColor(0.04, 0.025, 0.015, 0.55)
        box:SetBackdropBorderColor(0.55, 0.44, 0.28, 0.55)
    else
        box:SetBackdropColor(0.03, 0.02, 0.02, 0.55)
        box:SetBackdropBorderColor(F.accent[1] * 0.75, F.accent[2] * 0.75, F.accent[3] * 0.75, 0.9)
    end
end

function Theme.SetBook(on)
    Theme.book = on and true or false
    local c = on and BOOK or DARK
    Theme.LIGHT, Theme.DIM, Theme.LIGHT_MEND, Theme.LIGHT_RGB = c.LIGHT, c.DIM, c.LIGHT_MEND, c.rgb
    Theme.HALL_GOLD = on and "|cffffd100" or Theme.F().gold
    for fs, title in pairs(hallTexts) do colorText(fs, title) end
    for box in pairs(hallBoxes) do colorBox(box) end
    for b in pairs(Theme.hallButtons) do b:SetSelected(b.selected) end
end

-- Class colors for the hall: as they are on the dark hall, darkened on the book's pages.
function Theme.ClassHall(token)
    if Theme.book then return Theme.ClassInk(token) end
    return Theme.ClassLight(token)
end

-- A dark inset box with a thin border in the faction's accent (the boxes in Overlord's panel); a faint brown frame on
-- the book's pages.
function Theme.Inset(parent, noRules)
    local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
    end
    -- In the book a box is no box: just a divider above and below, which blends into the page.
    box.rules = {}
    for i, edge in ipairs(noRules and {} or { "TOP", "BOTTOM" }) do
        local rule = Theme.Rule(box, 100)
        rule:ClearAllPoints()
        rule:SetPoint(edge .. "LEFT", box, edge .. "LEFT", 6, i == 1 and 4 or -4)
        rule:SetPoint(edge .. "RIGHT", box, edge .. "RIGHT", -6, i == 1 and 4 or -4)
        box.rules[i] = rule
    end
    hallBoxes[box] = true
    colorBox(box)
    return box
end

-- A rule between sections on parchment, like in a book: a thin ink line that fades out towards both ends, with a
-- small diamond in the middle. Drawn from plain shapes, so it looks the same on every paper. (Blizzard's campaign
-- lore divider looked smudged and too short on the clean page.) Returns a frame `width` wide and 9 high.
local RULE_INK = { 0.24, 0.13, 0.06 }

local RULE_LIGHT = { 0.78, 0.64, 0.40 } -- on dark pages

local function fade(tex, fromAlpha, toAlpha, color)
    local r, g, b = (color or RULE_INK)[1], (color or RULE_INK)[2], (color or RULE_INK)[3]
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha("HORIZONTAL", r, g, b, fromAlpha, r, g, b, toAlpha)
    else
        tex:SetColorTexture(r, g, b, (fromAlpha + toAlpha) / 2)
    end
end

function Theme.Rule(parent, width, light)
    local color = light and RULE_LIGHT or RULE_INK
    local rule = CreateFrame("Frame", nil, parent)
    rule:SetSize(width, 9)
    -- The halves follow the frame's width, so a rule can also be stretched between two anchors.
    local left = rule:CreateTexture(nil, "ARTWORK")
    left:SetHeight(1)
    left:SetPoint("LEFT", 0, 0)
    left:SetPoint("RIGHT", rule, "CENTER", -8, 0) -- leave room for the diamond
    fade(left, 0, 0.75, color)
    local right = rule:CreateTexture(nil, "ARTWORK")
    right:SetHeight(1)
    right:SetPoint("RIGHT", 0, 0)
    right:SetPoint("LEFT", rule, "CENTER", 8, 0)
    fade(right, 0.75, 0, color)
    local diamond = rule:CreateTexture(nil, "ARTWORK")
    diamond:SetSize(6, 6)
    diamond:SetPoint("CENTER")
    diamond:SetColorTexture(color[1], color[2], color[3], 0.85)
    if diamond.SetRotation then diamond:SetRotation(math.pi / 4) end
    return rule
end

-- Text on parchment: body font, ink color.
function Theme.Text(parent, size, justify, title)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 13, title)
    fs:SetTextColor(Theme.INK_RGB[1], Theme.INK_RGB[2], Theme.INK_RGB[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Text in the hall: light (gold for titles) on the dark hall, ink (faction ink for titles) in the book. It follows
-- Theme.SetBook; text on buttons and bars, which stay dark either way, opts out with keepColor.
function Theme.LightText(parent, size, justify, title, keepColor)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme.Font(fs, size or 13, title)
    fs.kkSize = size or 13
    if keepColor then
        if title then fs:SetTextColor(1, 0.82, 0.45) else fs:SetTextColor(DARK_RGB[1], DARK_RGB[2], DARK_RGB[3]) end
    else
        hallTexts[fs] = title and true or false
        colorText(fs, title)
    end
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

Theme.hallButtons = setmetatable({}, { __mode = "k" })

-- Makes a hall button a link in the book (the contents, the periods): see SetSelected. Docked it stays a button.
function Theme.LinkStyle(b)
    b.kkLink = true
    b.marker = b:CreateTexture(nil, "ARTWORK")
    b.marker:SetSize(7, 7)
    b.marker:SetPoint("RIGHT", b.icon or b.label, "LEFT", -6, 0) -- in front of the icon, not squeezed after it
    b.marker:SetColorTexture(1, 0.82, 0, 1)
    if b.marker.SetRotation then b.marker:SetRotation(math.pi / 4) end
    b:SetSelected(b.selected)
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
    local text = Theme.LightText(b, 13, icon and "LEFT" or "CENTER", false, true)
    text:SetTextColor(1, 0.82, 0.45)
    if icon then text:SetPoint("LEFT", x, 0) else text:SetPoint("CENTER") end
    text:SetText(label)
    b.label = text
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(F.accent[1], F.accent[2], F.accent[3], 0.25)
    b.hl = hl
    Theme.hallButtons[b] = true
    -- Dark hall: a dark face in the faction's color, gold label, a bright border when chosen. Book: part of the page,
    -- a faint brown frame with an ink label, and a warm brown wash with an amber label when chosen.
    function b:SetSelected(on)
        self.selected = on
        if not self.SetBackdropColor then return end
        if Theme.book and self.kkLink then
            -- A link on the page (the contents, the periods): light text, no frame; the chosen one gold with a diamond.
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
            if on then self.label:SetTextColor(1, 0.82, 0) else self.label:SetTextColor(0.90, 0.85, 0.76) end
            self.marker:SetShown(on)
            self.hl:SetColorTexture(1, 0.82, 0.4, 0.08)
        elseif Theme.book or self.kkSheet then
            -- A plain dark button with a thin tan border (the Oracle's "Quest details").
            if on then
                self:SetBackdropColor(0.30, 0.20, 0.08, 0.90)
                self:SetBackdropBorderColor(1, 0.82, 0.4, 0.9)
                self.label:SetTextColor(1, 0.82, 0)
            else
                self:SetBackdropColor(0.07, 0.05, 0.03, 0.85)
                self:SetBackdropBorderColor(0.62, 0.52, 0.36, 0.75)
                self.label:SetTextColor(0.92, 0.87, 0.79)
            end
            self.hl:SetColorTexture(1, 0.82, 0.4, 0.10)
        else
            if self.marker then self.marker:Hide() end
            if on then
                self:SetBackdropBorderColor(1, 0.82, 0.4, 1)
                self:SetBackdropColor(F.accent[1] * 0.55, F.accent[2] * 0.55, F.accent[3] * 0.55, 0.95)
            else
                self:SetBackdropBorderColor(F.accent[1] * 0.8, F.accent[2] * 0.8, F.accent[3] * 0.8, 0.9)
                self:SetBackdropColor(F.button[1], F.button[2], F.button[3], 0.95)
            end
            self.label:SetTextColor(1, 0.82, 0.45)
            self.hl:SetColorTexture(F.accent[1], F.accent[2], F.accent[3], 0.25)
        end
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
    bar.text = Theme.LightText(bar, 11, "CENTER", false, true)
    bar.text:SetPoint("CENTER")
    function bar:SetProgress(value, goal)
        self:SetMinMaxValues(0, math.max(goal, 1))
        self:SetValue(math.min(value, goal))
        self.text:SetText(("%d / %d"):format(value, goal))
    end
    return bar
end
