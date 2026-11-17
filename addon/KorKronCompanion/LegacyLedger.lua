--[[
  The War Ledger inside Forever's Legacy window: one more category, "Kor'kron War Ledger", at the end of the Legacy
  challenge categories. Choosing it puts our own cards where Blizzard's challenges are: a card of fun numbers, then the
  War Ledger's tiered challenges (Ledger.Tracks), drawn with the Legacy window's own card and bar art.

  How it fits in without changing Blizzard's code (Blizzard_LegacySystem, from Gethe/wow-ui-source, forever branch):
    - The category list is rebuilt from achievement categories in ChallengesPage:UpdateCategoryList(). We add our entry
      after each rebuild (hooksecurefunc). It has no achievements (hasAchievements = false), so Blizzard's own selection
      never fires for it, and its id (a string) matches nothing of theirs.
    - CategoryList:SelectCategory() is hooked: ours shows our pane over the challenge pane (DetailPane hidden meanwhile);
      one of theirs hides it again, as do Blizzard selecting a category and the page closing.
    - The selected look of the list buttons is put right after Blizzard refreshes it.
  If any of these names change in a client patch, nothing is added and the Legacy window works as before.
]]

local _, KKC = ...
local Theme = KKC.Theme
local LL = {}
KKC.LegacyLedger = LL

local CATEGORY = "KorKronWarLedger"
local page, list, pane

local function ours() return pane and pane:IsShown() end

local function atlas(tex, name, useSize, r, g, b, a)
    if Theme.Atlas(tex, name, useSize) then return true end
    if r then tex:SetColorTexture(r, g, b, a or 1) end
    return false
end

-- ------------------------------------------------------------------------------------------------
-- Cards
-- ------------------------------------------------------------------------------------------------

local CARD_H = 104
local STAT_ROW = 18

-- Background: the Legacy card, in three pieces for the taller fun-numbers card (as Blizzard's expanded cards do).
local function background(f)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    atlas(f.bg, "Legacy-Challenge-Cards", false, 0.12, 0.08, 0.05, 0.9)
    f.top = f:CreateTexture(nil, "BACKGROUND")
    f.top:SetPoint("TOPLEFT"); f.top:SetPoint("TOPRIGHT")
    f.bottom = f:CreateTexture(nil, "BACKGROUND")
    f.bottom:SetPoint("BOTTOMLEFT"); f.bottom:SetPoint("BOTTOMRIGHT")
    f.middle = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.middle:SetPoint("TOPLEFT", 0, -10); f.middle:SetPoint("BOTTOMRIGHT", 0, 10)
    f.tiled = atlas(f.top, "Legacy-Challenge-Cards-tiled-top", true)
        and atlas(f.bottom, "Legacy-Challenge-Cards-tiled-bottom", true)
        and atlas(f.middle, "Legacy-Challenge-Cards-tiled-vertical", false)
    if f.tiled and f.middle.SetVertTile then f.middle:SetVertTile(true) end
end

local function setTall(f, tall)
    local tiled = tall and f.tiled
    f.bg:SetShown(not tiled)
    f.top:SetShown(tiled); f.bottom:SetShown(tiled); f.middle:SetShown(tiled)
end

local function buildCard(f)
    background(f)
    f.ribbon = f:CreateTexture(nil, "ARTWORK")
    f.ribbon:SetPoint("TOPLEFT", 5, -4)
    f.ribbon:SetPoint("TOPRIGHT", -80, -4)
    if not atlas(f.ribbon, "Legacy-Challenge-Cards-Ribbon-Brown", true) then f.ribbon:SetHeight(40) end

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(50, 50)
    f.icon:SetPoint("TOPLEFT", 17, -23)
    if f.CreateMaskTexture then
        local mask = f:CreateMaskTexture()
        if Theme.Atlas(mask, "UI-Frame-IconMask") then
            mask:SetAllPoints(f.icon)
            f.icon:AddMaskTexture(mask)
        else
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    f.frame = f:CreateTexture(nil, "OVERLAY")
    f.frame:SetPoint("CENTER", f.icon)
    if not atlas(f.frame, "Legacy-Tree-Frame-icon-frame", true) then f.frame:Hide() end

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.label:SetPoint("TOPLEFT", f.ribbon, "TOPLEFT", 70, -18)
    f.label:SetPoint("RIGHT", f, "RIGHT", -90, 0)
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)
    f.text = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    f.text:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 2, -8)
    f.text:SetPoint("RIGHT", f, "RIGHT", -24, 0) -- under the tier corner too: one line on the hall's narrower page
    f.text:SetJustifyH("LEFT")

    -- Progress to the next tier: the Legacy bar.
    f.barBg = f:CreateTexture(nil, "ARTWORK")
    f.barBg:SetSize(280, 16)
    f.barBg:SetPoint("BOTTOMLEFT", 88, 14)
    atlas(f.barBg, "Legacy-Progressbar-BG", false, 0, 0, 0, 0.6)
    -- Built from the Legacy art itself, not Blizzard's LegacyProgressBarTemplate: that template only exists once the
    -- Legacy window has been opened, so cards made before it got a plain bar and later ones the real one.
    local bar = CreateFrame("StatusBar", nil, f)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    if Theme.Atlas(fill, "Legacy-Progressbar-Fill") then
        bar:SetStatusBarTexture(fill)
    else
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.85, 0.65, 0.2)
    end
    local edge = bar:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPLEFT", -8, 7)
    edge:SetPoint("BOTTOMRIGHT", 8, -10)
    if not Theme.Atlas(edge, "Legacy-Progressbar-Frame") then edge:Hide() end
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    bar.Text:SetPoint("CENTER")
    bar:SetPoint("TOPLEFT", f.barBg, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", f.barBg, "BOTTOMRIGHT", 0, 3)
    bar:SetMinMaxValues(0, 1)
    f.bar = bar

    -- Right corner: the tier, or a check once every tier is earned.
    f.tier = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.tier:SetPoint("TOPRIGHT", -16, -16)
    f.tier:SetJustifyH("RIGHT")
    f.checkBg = f:CreateTexture(nil, "OVERLAY")
    f.checkBg:SetPoint("TOPRIGHT", -6, -3)
    atlas(f.checkBg, "Legacy-Challenge-Cards-Date-BG", true)
    f.check = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.check:SetPoint("TOPRIGHT", -10, -6)
    if atlas(f.check, "worldquest-tracker-checkmark", true) then f.check:SetScale(0.5) end

    -- The fun numbers: label and value pairs in two columns (summary card only).
    f.stats = {}
end

local function statLine(f, i)
    local s = f.stats[i]
    if s then return s end
    s = {}
    s.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.label:SetJustifyH("LEFT")
    s.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.value:SetJustifyH("LEFT")
    s.value:SetWordWrap(false)
    f.stats[i] = s
    return s
end

-- width: the card's width when it isn't the Legacy pane's (the hall's narrower page); nil there.
local WIDE = 520
local function initChallenge(f, t, width)
    setTall(f, false)
    f.barBg:SetWidth(math.max(120, math.min(280, (width or WIDE) - 88 - 24)))
    f.icon:SetTexture(t.icon)
    f.icon:SetDesaturated(t.tier == 0)
    f.label:SetText(t.title)
    f.text:SetText(t.text)
    f.barBg:Show(); f.bar:Show()
    f.bar:SetValue(t.goal > 0 and math.min(t.value / t.goal, 1) or 1)
    if type(f.bar.Text) == "table" then f.bar.Text:SetText(("%d / %d"):format(math.min(t.value, t.goal), t.goal)) end
    f.check:SetShown(t.complete); f.checkBg:SetShown(t.complete)
    f.tier:SetText(t.complete and "" or ("Tier %d of %d"):format(t.tier + 1, t.tiers))
    for _, s in ipairs(f.stats) do s.label:Hide(); s.value:Hide() end
end

-- Two columns of fun numbers on a wide card, one on a narrow one.
local function columns(width) return (width or WIDE) >= 480 and 2 or 1 end

local function initSummary(f, stats, width)
    setTall(f, true)
    f.icon:SetTexture(Theme.F().icon)
    f.icon:SetDesaturated(false)
    f.label:SetText("War Ledger of " .. (KKC.me() or "?"))
    f.text:SetText("Your own killing blows and honor kills only, so sharing with guildies never counts a kill twice.")
    f.barBg:Hide(); f.bar:Hide()
    f.check:Hide(); f.checkBg:Hide()
    f.tier:SetText("")
    local cols = columns(width)
    local half = math.ceil(#stats / cols)
    local colW = ((width or WIDE) - 40) / cols
    for i, kv in ipairs(stats) do
        local s = statLine(f, i)
        local col, row = i <= half and 0 or 1, (i <= half and i or i - half) - 1
        s.label:ClearAllPoints()
        s.label:SetPoint("TOPLEFT", f, "TOPLEFT", 24 + col * colW, -86 - row * STAT_ROW)
        s.value:ClearAllPoints()
        s.value:SetPoint("LEFT", s.label, "LEFT", 122, 0)
        s.value:SetWidth(colW - 126)
        s.label:SetText(kv[1])
        s.value:SetText(kv[2])
        s.label:Show(); s.value:Show()
    end
    for i = #stats + 1, #f.stats do f.stats[i].label:Hide(); f.stats[i].value:Hide() end
end

local function summaryHeight(n, width) return 86 + math.ceil(n / columns(width)) * STAT_ROW + 18 end

-- The same cards in the hall's War Ledger (Hub.lua), so both look alike.
LL.Cards = { Build = buildCard, Challenge = initChallenge, Summary = initSummary, SummaryHeight = summaryHeight, HEIGHT = CARD_H }

-- ------------------------------------------------------------------------------------------------
-- The pane over Blizzard's challenge pane
-- ------------------------------------------------------------------------------------------------

local function buildPane()
    local d = page.DetailPane
    local p = CreateFrame("Frame", nil, page)
    p:SetAllPoints(d)
    p:SetFrameLevel(d:GetFrameLevel() + 1)
    p:Hide()

    p.scroll = CreateFrame("Frame", nil, p, "WowScrollBoxList")
    p.scroll:SetPoint("TOPLEFT", 4, -3)
    p.scroll:SetPoint("BOTTOMRIGHT", 0, 5)
    p.bar = CreateFrame("EventFrame", nil, p, "MinimalScrollBar")
    p.bar:SetPoint("TOPLEFT", p.scroll, "TOPRIGHT", 6, -5)
    p.bar:SetPoint("BOTTOMLEFT", p.scroll, "BOTTOMRIGHT", 6, 1)
    if p.scroll.SetEdgeFadeLength then p.scroll:SetEdgeFadeLength(30) end

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 5)
    view:SetElementInitializer("Frame", function(f, data)
        if not f.kkcBuilt then buildCard(f); f.kkcBuilt = true end
        if data.summary then initSummary(f, data.summary) else initChallenge(f, data.track) end
    end)
    view:SetElementExtentCalculator(function(_, data)
        return data.summary and summaryHeight(#data.summary) or CARD_H
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(p.scroll, p.bar, view)

    function p:Refresh()
        local items = { { summary = KKC.Ledger.Highlights() } }
        for _, t in ipairs(KKC.Ledger.Tracks()) do items[#items + 1] = { track = t } end
        self.scroll:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
    end
    return p
end

-- Our list button selected while our pane shows, theirs not (Blizzard's selection still holds the last category).
local function fixSelection()
    if not (list and list.ScrollBox) then return end
    local mine = ours()
    list.ScrollBox:ForEachFrame(function(button)
        local data = button.GetData and button:GetData()
        if data and data.GetData then data = data:GetData() end
        if type(data) ~= "table" or not button.SetSelected then return end
        if data.kkc then button:SetSelected(mine)
        elseif mine then button:SetSelected(false) end
    end)
end

local function hidePane()
    if not ours() then return end
    pane:Hide()
    page.DetailPane:Show()
    if list.RefreshCategorySelectionVisuals then list:RefreshCategorySelectionVisuals() end -- theirs as they were
end

local function showPane()
    pane = pane or buildPane()
    page.DetailPane:Hide()
    pane:Show()
    pane:Refresh()
    fixSelection()
end
LL.Show = showPane

local function addCategory()
    local dp = list.ScrollBox:GetDataProvider()
    if not dp then return end
    -- While searching, the list shows only matching challenges; ours has none.
    local search = list.SearchBox and list.SearchBox:GetText()
    if search and search ~= "" then return end
    dp:Insert({ categoryInfo = { id = CATEGORY, name = "Kor'kron War Ledger" }, hasAchievements = false, kkc = true })
end

local function attach()
    if page then return end
    local L = LegacySystemFrame
    local p = L and L.ChallengesPage
    local cl = p and p.CategoryList
    if not (p and cl and cl.ScrollBox and p.DetailPane and p.UpdateCategoryList and cl.SelectCategory
        and CreateScrollBoxListLinearView and ScrollUtil and CreateDataProvider) then
        return -- the Legacy window isn't what this was written for: leave it alone
    end
    page, list = p, cl
    hooksecurefunc(page, "UpdateCategoryList", function() pcall(addCategory) end)
    hooksecurefunc(list, "SelectCategory", function(_, data)
        if type(data) ~= "table" then return end
        if data.kkc then showPane() elseif data.hasAchievements then hidePane() end
    end)
    if list.RefreshCategorySelectionVisuals then hooksecurefunc(list, "RefreshCategorySelectionVisuals", fixSelection) end
    if EventRegistry then EventRegistry:RegisterCallback("Legacy.SelectChallengeCategory", hidePane, LL) end
    page:HookScript("OnHide", hidePane)
    if page:IsShown() then pcall(addCategory) end
end

KKC.On("ADDON_LOADED", function(name) if name == "Blizzard_LegacySystem" then attach() end end)
KKC.Listen("Init", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and KKC.try(C_AddOns.IsAddOnLoaded, "Blizzard_LegacySystem")
    if loaded then attach() end
end)
KKC.Listen("EngagementClosed", function() if ours() then pane:Refresh() end end)
