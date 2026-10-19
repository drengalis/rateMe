local _, A = ...
local GOLD = {1, 0.72, 0.28}
local WHITE = {0.93, 0.91, 0.86}
local MUTED = {0.60, 0.64, 0.70}

-- One set of coordinates for both list headings and their row contents.
-- Headers are positioned on the main window, while rows are relative to the
-- scrolling content, which begins LIST_VIEWPORT_X pixels from the left edge.
local LIST_VIEWPORT_X = 29
local LIST_PAGE_SIZE = 20
local LIST_COLUMNS = {
    player = {x = 8, width = 235},
    rating = {x = 253, width = 157},
    date = {x = 418, width = 237},
}

local function makeFrame(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- The opaque full-frame texture also covers the border insets; the default
    -- Blizzard dialog background texture has transparent areas.
    local background = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(f)
    background:SetColorTexture(0.055, 0.065, 0.09, 1)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 28,
        insets = {left = 8, right = 8, top = 8, bottom = 8},
    })
    f:SetBackdropColor(0.055, 0.065, 0.09, 1)
    f:SetAlpha(1)
    -- WoW closes named frames registered here when Escape is pressed.
    if UISpecialFrames then
        local found = false
        for _, registered in ipairs(UISpecialFrames) do
            if registered == name then found = true; break end
        end
        if not found then table.insert(UISpecialFrames, name) end
    end
    f:SetScript("OnShow", function(self)
        if A.MarkWindowShown then A:MarkWindowShown(self) end
        if A.ArrangeWindows then A:ArrangeWindows() end
    end)
    f:SetScript("OnHide", function()
        if A.ArrangeWindows then A:ArrangeWindows() end
    end)
    f:Hide()
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide() end)
    return f
end

-- Tile the visible windows into one horizontal row, centred on the screen.
-- Sizes are in UIParent coordinates; a common scale ensures even small screens
-- never put one Rate Me! window on top of another.
function A:ArrangeWindows()
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then return end
    local frames = {}
    local totalWidth, maxHeight = 0, 0
    for _, windowName in ipairs({"main", "editor", "reviews", "partyReview", "reportHelp"}) do
        local frame = self[windowName]
        if frame and frame:IsShown() then
            frames[#frames + 1] = frame
            totalWidth = totalWidth + frame:GetWidth()
            maxHeight = math.max(maxHeight, frame:GetHeight())
        end
    end
    if #frames == 0 then return end

    local padding = 24
    local availableWidth = math.max(1, UIParent:GetWidth() - padding * 2)
    local availableHeight = math.max(1, UIParent:GetHeight() - padding * 2)
    local gap = math.min(18, (availableWidth - 1) / math.max(1, #frames - 1))
    local scale = math.min(1,
        (availableWidth - gap * (#frames - 1)) / totalWidth,
        availableHeight / maxHeight)
    scale = math.max(0.01, scale)
    local usedWidth = totalWidth * scale + gap * (#frames - 1)
    local nextLeft = -usedWidth / 2
    for _, frame in ipairs(frames) do
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", UIParent, "CENTER", nextLeft, 0)
        nextLeft = nextLeft + frame:GetWidth() * scale + gap
    end
end

-- Track which dialog was most recently opened, including when a visible editor
-- is reopened from the reviews window. This is also used for focused edit boxes.
function A:MarkWindowShown(frame)
    self.windowSequence = (self.windowSequence or 0) + 1
    frame.rateMeShowOrder = self.windowSequence
end

-- Edit boxes consume Escape themselves, so close the most recently opened
-- Rate Me! window instead of merely clearing focus.
function A:CloseTopWindow()
    local newest, newestOrder
    for _, windowName in ipairs({"main", "editor", "reviews", "partyReview", "reportHelp"}) do
        local frame = self[windowName]
        if frame and frame:IsShown() then
            local order = frame.rateMeShowOrder or 0
            if not newest or order > newestOrder then
                newest, newestOrder = frame, order
            end
        end
    end
    if newest then newest:Hide() end
end

local function label(parent, font, text, x, y, width, justification)
    local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then s:SetWidth(width) end
    if justification then s:SetJustifyH(justification) end
    s:SetText(text or "")
    return s
end

local function button(parent, text, width, height, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Stored timestamps are UTC-based Unix epoch seconds. WoW's date() uses
-- the player's local client timezone unless the format starts with "!".
-- Keep the conversion at display time, never in SavedVariables or packets.
function A:DateText(timestamp, includeSeconds)
    if type(timestamp) ~= "number" or timestamp <= 0 then return "Unknown" end
    return date(includeSeconds and "%Y-%m-%d %I:%M:%S %p" or "%Y-%m-%d %I:%M %p", timestamp)
end
-- Window-only presentation: 5 textures (empty/half/full to the closest 0.5),
-- followed immediately by the actual average rounded independently to 0.1.
-- Do not use this function for game tooltips, which remain stars-only.
function A:WindowScoreText(score, size)
    local value = tonumber(score)
    if not value then return "No ratings" end
    value = math.max(0, math.min(5, value))
    local roundedTenth = math.floor(value * 10 + 0.5) / 10
    return self:StarMarkup(value, size) .. " " .. string.format("%.1f", roundedTenth)
end

function A:ScoreText(summary)
    if not summary or not summary.average or summary.count == 0 then return "No ratings available" end
    local text = self:WindowScoreText(summary.average, 15) .. string.format("  (%d rating%s)",
        summary.count, summary.count == 1 and "" or "s")
    if not summary.fresh then text = text .. "  [cached]" end
    return text
end

function A:NotifyUI()
    if self.main and self.main:IsShown() then self:DrawMain() end
    if self.editor and self.editor:IsShown() then self:UpdateEditorSummary() end
    if self.reviews and self.reviews:IsShown() then self:DrawReviews() end
end

-- Lists always show their newest dated entries first. For authored reviews,
-- date is the latest time the owner saved the review; for community lookups,
-- checked is the last successful lookup and viewed is a fallback for entries
-- that have not yet received any network response.
local function sortItems(items, recent)
    local function stamp(item)
        if recent then
            return tonumber(item.checked) or tonumber(item.viewed) or 0
        end
        return tonumber(item.date) or 0
    end
    table.sort(items, function(a, b)
        local at, bt = stamp(a), stamp(b)
        if at ~= bt then return at > bt end
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        if an ~= bn then return an < bn end
        return tostring(a.guid or a.owner or "") < tostring(b.guid or b.owner or "")
    end)
end

function A:CreateMainWindow()
    local f = makeFrame("RateMeMainWindow", 770, 565)
    -- Keep the title and navigation in one header row. The close button
    -- occupies the far right, so the three tabs end before its hit area.
    -- Both text fields use the same left edge AND LEFT justification. The
    -- default centred justification on different widths shifted the tagline.
    f.title = label(f, "GameFontNormalLarge", "Rate Me!", 26, -24, 160, "LEFT")
    f.tagline = label(f, "GameFontDisableSmall", "Reputation earned. Reputation shared.", 26, -51, 325, "LEFT")
    f.tab = "mine"
    f.pages = {mine = 1, recent = 1}
    f.tabMine = button(f, "My Ratings", 107, 27, 370, -19, function()
        f.tab = "mine"; f.selected = nil; A:DrawMain()
    end)
    f.tabRecent = button(f, "Recent Lookups", 132, 27, 482, -19, function()
        f.tab = "recent"; f.selected = nil; A:DrawMain()
    end)
    f.tabSettings = button(f, "Settings", 98, 27, 619, -19, function()
        f.tab = "settings"; f.selected = nil; A:DrawMain()
    end)
    -- Keep the title/navigation, list, and pagination/search visually distinct
    -- without adding extra headers or taking space away from the scroll area.
    -- Plain colour textures are supported by Forever's client and scale with
    -- the window, unlike fixed-width decorative character glyphs.
    local function divider(y)
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(0.30, 0.35, 0.43, 0.9)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 29, y)
        line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -29, y)
        return line
    end
    f.headerDivider = divider(-81)
    -- A fine line also fixes the column headings visually above scrolling rows.
    f.listHeadingDivider = f:CreateTexture(nil, "ARTWORK")
    f.listHeadingDivider:SetHeight(1)
    f.listHeadingDivider:SetColorTexture(0.30, 0.35, 0.43, 0.55)
    f.listHeadingDivider:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_VIEWPORT_X, -117)
    f.listHeadingDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -117)
    -- Pagination belongs to the results area. Put the divider *below* its
    -- controls, then use the darker footer only for Search and Clear.
    f.footerBackground = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.footerBackground:SetColorTexture(0.038, 0.045, 0.065, 1)
    f.footerBackground:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -506)
    f.footerBackground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -25, 12)
    f.footerDivider = divider(-506)
    -- Search is the only footer control. All Characters lives in Settings,
    -- and lookup refresh remains in the selected player's drilldown window.
    -- Player counts sit right-aligned on the same row as the pager instead of
    -- floating in the blank space above the column headings.
    f.status = label(f, "GameFontDisableSmall", "", 588, -477, 153, "RIGHT")
    f.searchLabel = label(f, "GameFontNormalSmall", "Search:", 29, -526)
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(400, 23)
    f.search:SetPoint("TOPLEFT", 72, -520)
    -- InputBoxTemplate draws a frame *outside* the EditBox bounds. Position
    -- the label against the visible border, not against its hidden frame edge.
    -- Vertical adjustments account for the small-font glyph's visible centre.
    f.searchLabel:ClearAllPoints()
    f.searchLabel:SetPoint("RIGHT", f.search, "LEFT", -13, 1)
    f.searchLabel:SetJustifyH("RIGHT")
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(70)
    f.search:SetScript("OnTextChanged", function(self)
        f.pages.mine, f.pages.recent = 1, 1
        f.selected = nil
        if f.clearSearch then
            local text = self:GetText() or ""
            f.clearSearch:SetEnabled(text ~= "")
        end
        A:DrawMain()
    end)
    f.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        A:CloseTopWindow()
    end)
    f.clearSearch = button(f, "X", 24, 24, 478, -518, function()
        if not f.search then return end
        f.search:SetText("")
        f.search:ClearFocus()
        f.selected = nil
        A:DrawMain()
    end)
    -- Match the actual visual centre of the rendered input border; the button
    -- texture has slightly uneven top/bottom padding of its own.
    f.clearSearch:ClearAllPoints()
    f.clearSearch:SetPoint("LEFT", f.search, "RIGHT", 6, -1)
    f.clearSearch:SetEnabled(false)
    -- Static column headings only: date-descending is now the sole sort order.
    -- Align heading boundaries exactly with the text bounds of each row.
    f.playerHeading = label(f, "GameFontNormalSmall", "Player",
        LIST_VIEWPORT_X + LIST_COLUMNS.player.x, -97, LIST_COLUMNS.player.width, "RIGHT")
    f.ratingHeading = label(f, "GameFontNormalSmall", "Rating",
        LIST_VIEWPORT_X + LIST_COLUMNS.rating.x, -97, LIST_COLUMNS.rating.width, "RIGHT")
    f.dateHeading = label(f, "GameFontNormalSmall", "Date rated",
        LIST_VIEWPORT_X + LIST_COLUMNS.date.x, -97, LIST_COLUMNS.date.width, "RIGHT")
    f.scroller = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroller:SetPoint("TOPLEFT", LIST_VIEWPORT_X, -126)
    -- Reserve space for the pager and Search/action footer beneath it.
    f.scroller:SetPoint("BOTTOMRIGHT", -50, 108)
    f.content = CreateFrame("Frame", nil, f.scroller)
    f.content:SetSize(675, 1)
    f.scroller:SetScrollChild(f.content)
    f.scroller:SetScript("OnSizeChanged", function(scroll, width)
        if type(width) == "number" and width > 0 and f.content then
            f.content:SetWidth(math.max(675, width - 4))
        end
    end)
    f.rows = {}
    f.previousPage = button(f, "Previous", 95, 24, 244, -471, function()
        if f.tab ~= "mine" and f.tab ~= "recent" then return end
        local page = f.pages[f.tab] or 1
        if page <= 1 then return end
        f.pages[f.tab] = page - 1
        f.selected = nil
        A:DrawMain()
    end)
    f.pageIndicator = label(f, "GameFontHighlightSmall", "Page 1 of 1", 349, -477, 123, "CENTER")
    f.nextPage = button(f, "Next", 95, 24, 484, -471, function()
        if f.tab ~= "mine" and f.tab ~= "recent" then return end
        local page = f.pages[f.tab] or 1
        if page >= (f.pageCounts and f.pageCounts[f.tab] or 1) then return end
        f.pages[f.tab] = page + 1
        f.selected = nil
        A:DrawMain()
    end)
    f:SetScript("OnShow", function()
        A:MarkWindowShown(f)
        A:DrawMain()
        A:ArrangeWindows()
    end)
    self.main = f
end

-- Settings use opaque, self-contained sections. Dependent controls are inset
-- under their master switch; checkbox labels explain each option.
-- The preference keys and change handlers are unchanged (SavedVariables v1).
function A:CreateSettingsPanel()
    local scroll = CreateFrame("ScrollFrame", nil, self.main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", self.main, "TOPLEFT", 29, -97)
    scroll:SetPoint("BOTTOMRIGHT", self.main, "BOTTOMRIGHT", -38, 50)
    -- Keep the content just inside the scroll viewport, rather than the old
    -- hard-coded 665/640 widths that left a large unused strip on the right.
    -- Match future size changes (including UI-scale changes) automatically.
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(699, 1285) -- seven responsive sections, including optional debug output
    scroll:SetScrollChild(p)
    scroll.content = p
    scroll:SetScript("OnSizeChanged", function(_, width)
        if type(width) == "number" and width > 0 then
            p:SetWidth(math.max(400, width - 4))
        end
    end)
    if scroll.GetWidth then
        local width = scroll:GetWidth()
        if type(width) == "number" and width > 0 then
            p:SetWidth(math.max(400, width - 4))
        end
    end

    local function section(y, height, title)
        local card = CreateFrame("Frame", nil, p, "BackdropTemplate")
        card:SetHeight(height)
        -- Two horizontal anchors make each panel fill the available content width
        -- with matching 8px gutters, without running under the scrollbar.
        card:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -y)
        card:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -y)
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        card:SetBackdropColor(0.11, 0.13, 0.18, 1)
        card:SetBackdropBorderColor(0.28, 0.33, 0.41, 1)
        -- A previous 3px gold accent rendered as a stray glyph beside headings
        -- on Forever. Keep the gold heading without that decorative bar.
        local titleText = label(card, "GameFontNormalLarge", title, 20, -12)
        titleText:SetTextColor(unpack(GOLD))
        return card
    end

    local function rule(card, y)
        local tex = card:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(0.31, 0.36, 0.44, 1)
        tex:SetHeight(1)
        tex:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -y)
        tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", -20, -y)
        return tex
    end

    local function checkbox(card, key, title, x, y, onClick)
        local row = CreateFrame("Button", nil, card)
        row:SetSize(520 - x, 30)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        c:SetSize(30, 30)
        c:SetPoint("LEFT", row, "LEFT", 0, 0)
        local caption = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        caption:SetPoint("LEFT", c, "RIGHT", 6, 0)
        caption:SetText(title)
        caption:SetJustifyH("LEFT")
        -- Keep labels wide enough for their self-explanatory wording.
        local textWidth = caption.GetStringWidth and caption:GetStringWidth() or (#title * 7)
        caption:SetWidth(math.min(480 - x, math.ceil(textWidth + 5)))
        local function changed(self)
            A:SetSetting(key, self:GetChecked() and true or false)
            if onClick then onClick() end
            A:DrawSettings()
        end
        c:SetScript("OnClick", changed)
        row:SetScript("OnClick", function() c:SetChecked(not c:GetChecked()); changed(c) end)
        return c, row, caption
    end

    local function threshold(card, name, key, text, y)
        local heading = label(card, "GameFontHighlightSmall", text, 79, -y, 355)
        local value = label(card, "GameFontNormal", "", 460, -(y + 18), 151, "RIGHT")
        local slider = CreateFrame("Slider", name, card, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", card, "TOPLEFT", 85, -(y + 29))
        slider:SetSize(340, 19)
        slider:SetMinMaxValues(1, 5)
        slider:SetValueStep(0.5)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local base = slider:GetName()
        if base then
            if _G[base .. "Low"] then _G[base .. "Low"]:SetText("1.0") end
            if _G[base .. "High"] then _G[base .. "High"]:SetText("5.0") end
            if _G[base .. "Text"] then _G[base .. "Text"]:SetText("") end
        end
        slider:SetValue(A.db.settings[key])
        slider:SetScript("OnValueChanged", function(self, number)
            local rounded = math.max(1, math.min(5, math.floor(number * 2 + 0.5) / 2))
            if math.abs(number - rounded) > 0.001 then self:SetValue(rounded); return end
            if A.db.settings[key] ~= rounded then
                A:SetSetting(key, rounded)
                A:OnAlertSettingsChanged()
            end
            A:DrawSettings()
        end)
        return slider, value, heading
    end

    local myRatings = section(12, 90, "My Ratings")
    p.allCharacters, p.allCharactersRow, p.allCharactersLabel = checkbox(myRatings,
        "allCharacters", "Show ratings from all my characters in My Ratings", 19, 51,
        function()
            -- This changes only which saved personal records are shown.
            -- Keep per-character authorship and existing records untouched.
            self.main.pages.mine = 1
            self.main.selected = nil
        end)

    local alerts = section(121, 345, "Group Rating Alerts")
    p.enabled, p.enabledRow, p.enabledLabel = checkbox(alerts, "lowRatingAlerts",
        "Show a warning when a low-rated player joins my group", 19, 51,
        function() A:OnAlertSettingsChanged() end)
    rule(alerts, 91)
    p.alertPersonal, p.alertPersonalRow, p.alertPersonalLabel = checkbox(alerts, "lowRatingPersonal",
        "Check ratings I personally gave players", 43, 103,
        function() A:OnAlertSettingsChanged() end)
    p.personalThreshold, p.personalThresholdValue, p.personalThresholdLabel = threshold(alerts,
        "RateMePersonalAlertThresholdSlider", "lowRatingPersonalThreshold",
        "Warn if my rating is at or below", 141)
    p.alertCommunity, p.alertCommunityRow, p.alertCommunityLabel = checkbox(alerts, "lowRatingCommunity",
        "Check recent verified community ratings", 43, 225,
        function() A:OnAlertSettingsChanged() end)
    p.threshold, p.thresholdValue, p.thresholdLabel = threshold(alerts,
        "RateMeAlertThresholdSlider", "lowRatingThreshold",
        "Warn if community rating is at or below", 263)

    local highlights = section(485, 288, "Player Rating Highlights")
    p.highlights, p.highlightsRow, p.highlightsLabel = checkbox(highlights, "ratingHighlights",
        "Enable rating indicators for friendly players", 19, 51,
        function() A:OnHighlightSettingsChanged() end)
    rule(highlights, 89)
    p.highlightGlow, p.highlightGlowRow, p.highlightGlowLabel = checkbox(highlights,
        "ratingHighlightsGlow", "Show gold/red glows on player frames", 43, 100,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightBadge, p.highlightBadgeRow, p.highlightBadgeLabel = checkbox(highlights,
        "ratingHighlightsBadge", "Show a star with the numeric rating beside nameplates", 43, 135,
        function() A:OnHighlightSettingsChanged() end)
    rule(highlights, 172)
    p.highlightPersonal, p.highlightPersonalRow, p.highlightPersonalLabel = checkbox(highlights,
        "ratingHighlightsPersonal", "Use ratings I personally gave players", 43, 182,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightCommunity, p.highlightCommunityRow, p.highlightCommunityLabel = checkbox(highlights,
        "ratingHighlightsCommunity", "Use recent verified community ratings", 43, 217,
        function() A:OnHighlightSettingsChanged() end)
    local legend = label(highlights, "GameFontHighlightSmall",
        "Badge: community first, then personal.  Gold: 4.0+   Red: below 2.0", 47, -261, 610)
    legend:SetTextColor(unpack(MUTED))

    local party = section(792, 109, "Post-Party Ratings")
    p.partyReviewPrompt, p.partyReviewPromptRow, p.partyReviewPromptLabel = checkbox(party,
        "partyReviewPrompt", "Open the party rating popup when I leave a party", 19, 51,
        function() if not A.db.settings.partyReviewPrompt then A.pendingPartyReview = nil end end)
    local partyHint = label(party, "GameFontHighlightSmall",
        "Dismiss with Escape. Reopen the last party with /rateme party.", 55, -84, 545)
    partyHint:SetTextColor(unpack(MUTED))

    local comments = section(920, 109, "Comment Safety")
    p.hideCommentsByDefault, p.hideCommentsByDefaultRow, p.hideCommentsByDefaultLabel = checkbox(comments,
        "hideCommentsByDefault", "Keep reviews hidden until I choose to show them", 19, 51, function()
            A.revealedReviews = {}
            if A.reviews and A.reviews:IsShown() then A:DrawReviews() end
        end)
    local commentHint = label(comments, "GameFontHighlightSmall",
        "Show/Hide, Block and Report controls are available per review.", 55, -85, 545)
    commentHint:SetTextColor(unpack(MUTED))

    local minimap = section(1048, 109, "Minimap Button")
    p.minimapVisible, p.minimapVisibleRow, p.minimapVisibleLabel = checkbox(minimap,
        "minimapVisible", "Show the movable Rate Me! button on my minimap", 19, 51,
        function() A:SetMinimapVisible(A.db.settings.minimapVisible) end)
    local miniHint = label(minimap, "GameFontHighlightSmall",
        "Left-click: open     Left-drag: move     /rateme: always available", 55, -84, 545)
    miniHint:SetTextColor(unpack(MUTED))

    local diagnostics = section(1176, 90, "Diagnostics")
    p.debug, p.debugRow, p.debugLabel = checkbox(diagnostics,
        "debug", "Show rating and peer-to-peer activity in chat (debug)", 19, 51)

    -- Preserve original controls/aliases for any current callers or testing.
    for _, name in ipairs({"enabled", "alertPersonal", "alertCommunity", "threshold", "thresholdValue",
        "personalThreshold", "personalThresholdValue", "highlights", "highlightGlow", "highlightBadge",
        "highlightPersonal", "highlightCommunity", "minimapVisible", "partyReviewPrompt", "hideCommentsByDefault",
        "allCharacters", "debug"}) do
        scroll[name] = p[name]
    end
    self.main.settingsPanel = scroll
    scroll:Hide()
end

function A:DrawSettings()
    local f = self.main
    if not f or not f.settingsPanel then return end
    local p = f.settingsPanel.content
    local settings = self.db.settings
    p.allCharacters:SetChecked(settings.allCharacters)
    p.debug:SetChecked(settings.debug)
    p.enabled:SetChecked(settings.lowRatingAlerts)
    p.alertPersonal:SetChecked(settings.lowRatingPersonal)
    p.alertCommunity:SetChecked(settings.lowRatingCommunity)
    p.highlights:SetChecked(settings.ratingHighlights)
    p.highlightGlow:SetChecked(settings.ratingHighlightsGlow)
    p.highlightBadge:SetChecked(settings.ratingHighlightsBadge)
    p.highlightPersonal:SetChecked(settings.ratingHighlightsPersonal)
    p.highlightCommunity:SetChecked(settings.ratingHighlightsCommunity)
    p.minimapVisible:SetChecked(settings.minimapVisible)
    p.partyReviewPrompt:SetChecked(settings.partyReviewPrompt)
    p.hideCommentsByDefault:SetChecked(settings.hideCommentsByDefault)

    local function dependent(control, row, caption, isEnabled)
        control:SetEnabled(isEnabled)
        row:SetEnabled(isEnabled)
        caption:SetTextColor(isEnabled and 0.93 or 0.53,
            isEnabled and 0.91 or 0.56, isEnabled and 0.86 or 0.60)
    end
    dependent(p.alertPersonal, p.alertPersonalRow, p.alertPersonalLabel, settings.lowRatingAlerts)
    dependent(p.alertCommunity, p.alertCommunityRow, p.alertCommunityLabel, settings.lowRatingAlerts)
    dependent(p.highlightGlow, p.highlightGlowRow, p.highlightGlowLabel, settings.ratingHighlights)
    dependent(p.highlightBadge, p.highlightBadgeRow, p.highlightBadgeLabel, settings.ratingHighlights)
    local anyVisual = settings.ratingHighlights and
        (settings.ratingHighlightsGlow or settings.ratingHighlightsBadge)
    dependent(p.highlightPersonal, p.highlightPersonalRow, p.highlightPersonalLabel, anyVisual)
    dependent(p.highlightCommunity, p.highlightCommunityRow, p.highlightCommunityLabel, anyVisual)
    local personalEnabled = settings.lowRatingAlerts and settings.lowRatingPersonal
    local communityEnabled = settings.lowRatingAlerts and settings.lowRatingCommunity
    p.personalThreshold:SetEnabled(personalEnabled)
    p.threshold:SetEnabled(communityEnabled)
    p.personalThreshold:SetAlpha(personalEnabled and 1 or 0.42)
    p.threshold:SetAlpha(communityEnabled and 1 or 0.42)
    p.personalThresholdLabel:SetTextColor(personalEnabled and 0.93 or 0.53,
        personalEnabled and 0.91 or 0.56, personalEnabled and 0.86 or 0.60)
    p.thresholdLabel:SetTextColor(communityEnabled and 0.93 or 0.53,
        communityEnabled and 0.91 or 0.56, communityEnabled and 0.86 or 0.60)
    if math.abs(p.threshold:GetValue() - settings.lowRatingThreshold) > 0.001 then
        p.threshold:SetValue(settings.lowRatingThreshold)
    end
    if math.abs(p.personalThreshold:GetValue() - settings.lowRatingPersonalThreshold) > 0.001 then
        p.personalThreshold:SetValue(settings.lowRatingPersonalThreshold)
    end
    p.thresholdValue:SetText(string.format("%.1f stars or lower", settings.lowRatingThreshold))
    p.personalThresholdValue:SetText(string.format("%.1f stars or lower", settings.lowRatingPersonalThreshold))
    p.thresholdValue:SetTextColor(communityEnabled and 0.93 or 0.53,
        communityEnabled and 0.91 or 0.56, communityEnabled and 0.86 or 0.60)
    p.personalThresholdValue:SetTextColor(personalEnabled and 0.93 or 0.53,
        personalEnabled and 0.91 or 0.56, personalEnabled and 0.86 or 0.60)
end

function A:CreateMainRow(index)
    local f = self.main
    local b = CreateFrame("Button", nil, f.content)
    b:SetHeight(38)
    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * 40)
    b:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -(index - 1) * 40)
    local tex = b:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0.19, 0.23, 0.30, index % 2 == 0 and 0.4 or 0.2)
    b.nameText = label(b, "GameFontHighlight", "",
        LIST_COLUMNS.player.x, -7, LIST_COLUMNS.player.width, "RIGHT")
    b.subText = label(b, "GameFontDisableSmall", "",
        LIST_COLUMNS.player.x, -23, LIST_COLUMNS.player.width, "RIGHT")
    b.scoreText = label(b, "GameFontNormal", "",
        LIST_COLUMNS.rating.x, -12, LIST_COLUMNS.rating.width, "RIGHT")
    b.dateText = label(b, "GameFontHighlightSmall", "",
        LIST_COLUMNS.date.x, -12, LIST_COLUMNS.date.width, "RIGHT")
    b:SetScript("OnClick", function(self)
        local item = self.record
        if not item then return end
        f.selected = item.guid
        if f.tab == "mine" then
            if item.owner == A:Key(A.myName) then
                A:OpenEditor(item)
            else
                A:Log("That rating was written by another character. Log in as that character to edit it.")
                A:OpenReviews(item)
            end
        else
            A:OpenReviews(item)
        end
    end)
    f.rows[index] = b
    return b
end

function A:DrawMain()
    local f = self.main
    if not f then return end
    f.tabMine:SetEnabled(f.tab ~= "mine")
    f.tabRecent:SetEnabled(f.tab ~= "recent")
    f.tabSettings:SetEnabled(f.tab ~= "settings")
    local isSettings = f.tab == "settings"
    f.settingsPanel:SetShown(isSettings)
    -- Settings has its own cards, not a list/pager/footer; keep the common
    -- header rule but hide every list-only separator and footer texture.
    f.listHeadingDivider:SetShown(not isSettings)
    f.footerBackground:SetShown(not isSettings)
    f.footerDivider:SetShown(not isSettings)
    f.searchLabel:SetShown(not isSettings)
    f.search:SetShown(not isSettings)
    f.clearSearch:SetShown(not isSettings)
    f.status:SetShown(not isSettings)
    f.scroller:SetShown(not isSettings)
    f.playerHeading:SetShown(not isSettings)
    f.ratingHeading:SetShown(not isSettings)
    f.dateHeading:SetShown(not isSettings)
    f.previousPage:SetShown(not isSettings)
    f.pageIndicator:SetShown(not isSettings)
    f.nextPage:SetShown(not isSettings)
    f.dateHeading:SetText(f.tab == "recent" and "Last checked" or "Date rated")
    f.clearSearch:SetEnabled((f.search:GetText() or "") ~= "")
    if isSettings then self:DrawSettings(); return end

    if f.scroller and f.scroller.GetWidth and f.content then
        local width = f.scroller:GetWidth()
        if type(width) == "number" and width > 0 then
            f.content:SetWidth(math.max(675, width - 4))
        end
    end
    local records = f.tab == "mine" and self:ListOwn() or self:ListRecent()
    local filter = f.search:GetText():lower()
    local items = {}
    for _, record in ipairs(records) do
        if record.name and (filter == "" or record.name:lower():find(filter, 1, true)
            or self:DisplayName(record.name):lower():find(filter, 1, true)) then
            items[#items + 1] = record
        end
    end
    -- Search the entire list and sort BEFORE applying pagination.
    sortItems(items, f.tab == "recent")
    local total = #items
    local pageCount = math.max(1, math.ceil(total / LIST_PAGE_SIZE))
    f.pageCounts = f.pageCounts or {}
    f.pageCounts[f.tab] = pageCount
    local page = math.max(1, math.min(f.pages[f.tab] or 1, pageCount))
    f.pages[f.tab] = page
    local first = (page - 1) * LIST_PAGE_SIZE + 1
    local last = math.min(page * LIST_PAGE_SIZE, total)
    f.status:SetText(total == 0 and "0 players" or
        string.format("%d-%d of %d players", first, last, total))
    f.pageIndicator:SetText(string.format("Page %d of %d", page, pageCount))
    f.previousPage:SetEnabled(page > 1)
    f.nextPage:SetEnabled(page < pageCount)
    -- Clear list selection if filtering/paging has moved it out of view.
    if f.selected then
        local visible = false
        for itemIndex = first, last do
            if items[itemIndex].guid == f.selected then visible = true; break end
        end
        if not visible then f.selected = nil end
    end

    local index = 0
    for itemIndex = first, last do
        local item = items[itemIndex]
        index = index + 1
        local row = f.rows[index] or self:CreateMainRow(index)
        row.record = item
        row.nameText:SetText(self:DisplayName(item.name))
        row.subText:SetText(item.class or (f.tab == "mine" and "Your review" or "Community lookup"))
        if f.tab == "mine" then
            row.scoreText:SetText(self:WindowScoreText(item.score, 14))
            row.dateText:SetText(self:DateText(item.date))
        else
            row.scoreText:SetText(item.score and (self:WindowScoreText(item.score, 13) .. " (" .. tostring(item.count or 0) .. ")")
                or "No ratings")
            row.dateText:SetText(self:DateText(item.checked) .. (item.fresh and "" or " [cached]"))
        end
        row:Show()
    end
    for rowIndex = index + 1, #f.rows do f.rows[rowIndex]:Hide() end
    f.content:SetHeight(math.max(1, index * 40))
    -- Do not jump back to the top on incoming rating updates, only on an actual
    -- change of tab, search, source filter, or page.
    local viewKey = table.concat({f.tab, filter, tostring(self.db.settings.allCharacters), tostring(page)}, "|")
    if f.lastListViewKey ~= viewKey then
        if f.scroller.SetVerticalScroll then f.scroller:SetVerticalScroll(0) end
        f.lastListViewKey = viewKey
    end
end

function A:CreateEditorWindow()
    local f = makeFrame("RateMeEditorWindow", 510, 520)
    label(f, "GameFontNormalLarge", "Rate Me!", 27, -26)
    f.targetText = label(f, "GameFontHighlight", "", 28, -67, 450)
    label(f, "GameFontNormal", "Community rating", 28, -110)
    f.community = label(f, "GameFontHighlight", "", 28, -134, 452)
    f.freshness = label(f, "GameFontDisableSmall", "", 28, -158, 452)
    label(f, "GameFontNormal", "Your rating", 28, -207)
    f.stars = {}
    f.score = 0
    for n = 1, 5 do
        local b = button(f, "", 65, 43, 28 + (n - 1) * 75, -232, function()
            f.score = n
            A:UpdateEditorStars()
        end)
        -- A texture is more reliable than a star character in Blizzard UI fonts.
        b.starTexture = b:CreateTexture(nil, "OVERLAY")
        b.starTexture:SetSize(29, 29)
        b.starTexture:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.starTexture:SetTexture(A.STAR_EMPTY_TEXTURE)
        f.stars[n] = b
    end
    -- Personal rating uses interactive star textures, plus a numeric score beside them.
    f.selectedNumeric = label(f, "GameFontHighlight", "", 405, -243, 74)
    f.scoreText = label(f, "GameFontHighlightSmall", "", 28, -285, 430)
    label(f, "GameFontNormal", "Your comment (optional)", 28, -312)
    -- InputBoxTemplate is a SINGLE-LINE visual: using it with SetMultiLine
    -- puts extra lines outside the thin input artwork. Instead, frame a real
    -- multi-line EditBox inside a clipped ScrollFrame. Its height grows with
    -- its text, while the viewport stays the same height.
    f.commentBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.commentBox:SetSize(432, 85)
    f.commentBox:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -339)
    f.commentBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    f.commentBox:SetBackdropColor(0.025, 0.03, 0.045, 1)
    f.commentBox:SetBackdropBorderColor(0.40, 0.44, 0.52, 1)

    -- The named UIPanelScrollFrameTemplate provides a visible scrollbar with
    -- mouse/keyboard/drag controls. Reserve a strip within the comment border.
    f.commentScroll = CreateFrame("ScrollFrame", "RateMeEditorCommentScrollFrame",
        f.commentBox, "UIPanelScrollFrameTemplate")
    f.commentScroll:SetPoint("TOPLEFT", f.commentBox, "TOPLEFT", 9, -8)
    f.commentScroll:SetPoint("BOTTOMRIGHT", f.commentBox, "BOTTOMRIGHT", -33, 8)
    f.commentBar = _G["RateMeEditorCommentScrollFrameScrollBar"]
    if f.commentBar then
        f.commentBar:ClearAllPoints()
        f.commentBar:SetPoint("TOPLEFT", f.commentScroll, "TOPRIGHT", 5, -15)
        f.commentBar:SetPoint("BOTTOMLEFT", f.commentScroll, "BOTTOMRIGHT", 5, 15)
        f.commentBar:Show()
    end
    f.commentScroll:EnableMouseWheel(true)
    f.commentScroll:SetScript("OnMouseWheel", function(scroll, delta)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(),
            scroll:GetVerticalScroll() - delta * 20)))
    end)
    f.commentScroll:SetScript("OnMouseDown", function() f.comment:SetFocus() end)

    f.comment = CreateFrame("EditBox", nil, f.commentScroll)
    f.comment:SetFontObject(ChatFontNormal or GameFontHighlight)
    f.comment:SetTextColor(0.96, 0.95, 0.91)
    f.comment:SetMultiLine(true)
    f.comment:SetWidth(382)
    f.comment:SetHeight(18) -- Multiline EditBoxes expand automatically as text wraps.
    f.comment:SetAutoFocus(false)
    f.comment:SetMaxLetters(self.MAX_COMMENT)
    if f.comment.SetMaxBytes then f.comment:SetMaxBytes(self.MAX_COMMENT) end
    if f.comment.SetSpacing then f.comment:SetSpacing(2) end
    f.commentScroll:SetScrollChild(f.comment)
    f.commentBox:SetScript("OnMouseDown", function() f.comment:SetFocus() end)
    -- Enter inserts a newline rather than saving/closing the rating window.
    f.comment:SetScript("OnEnterPressed", function(self)
        self:Insert("\n")
        -- Some clients do not fire OnTextChanged for programmatic Insert().
        if f.commentScroll.UpdateScrollChildRect then f.commentScroll:UpdateScrollChildRect() end
        if f.bytes then f.bytes:SetText(tostring(#self:GetText()) .. " / " .. A.MAX_COMMENT .. " bytes") end
    end)
    f.comment:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        A:CloseTopWindow()
    end)
    f.comment:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        if type(y) ~= "number" then return end
        local scroll = f.commentScroll
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        local cursorTop = math.max(0, -y)
        local cursorBottom = cursorTop + (type(lineHeight) == "number" and lineHeight or 14)
        local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
        if cursorTop < offset then
            scroll:SetVerticalScroll(cursorTop)
        elseif cursorBottom > offset + height then
            scroll:SetVerticalScroll(cursorBottom - height)
        end
    end)
    f.comment:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        -- SetText does not necessarily respect SetMaxBytes; enforce the actual
        -- UTF-8 byte limit for pasted or prefilled comments as well.
        if #text > A.MAX_COMMENT then
            self:SetText(A:UTF8SafeCut(text, A.MAX_COMMENT))
            return
        end
        if f.commentScroll.UpdateScrollChildRect then f.commentScroll:UpdateScrollChildRect() end
        if f.bytes then f.bytes:SetText(tostring(#text) .. " / " .. A.MAX_COMMENT .. " bytes") end
    end)
    f.bytes = label(f, "GameFontDisableSmall", "0 / 160 bytes", 28, -432, 432, "RIGHT")
    f.bytes:ClearAllPoints()
    f.bytes:SetPoint("TOPRIGHT", f.commentBox, "BOTTOMRIGHT", -3, -4)
    f.save = button(f, "Save Rating", 125, 26, 28, -463, function()
        local ok, err = A:SaveOwnRating(f.target, f.score, f.comment:GetText())
        if ok then
            f:Hide()
            A:Log("Saved your rating for " .. A:DisplayName(f.target.name))
        else
            A:Log(err or "Unable to save rating")
        end
    end)
    f.remove = button(f, "Remove", 86, 26, 158, -463, function()
        if A:DeleteOwnRating(f.target) then
            A:Log("Removed your rating for " .. A:DisplayName(f.target.name))
            f:Hide()
        end
    end)
    f.view = button(f, "Reviews", 93, 26, 250, -463, function() A:OpenReviews(f.target) end)
    button(f, "Cancel", 112, 26, 353, -463, function() f:Hide() end)
    self.editor = f
end

function A:UpdateEditorStars()
    local f = self.editor
    if not f then return end
    for n, b in ipairs(f.stars) do
        b.starTexture:SetTexture(n <= f.score and self.STAR_FULL_TEXTURE or self.STAR_EMPTY_TEXTURE)
    end
    f.selectedNumeric:SetText(f.score > 0 and string.format("%.1f", f.score) or "Not rated")
    f.scoreText:SetText(f.score > 0 and "Click another star to change your rating" or "Select a star to rate this player")
    f.save:SetEnabled(f.score > 0)
end
function A:UpdateEditorSummary()
    local f = self.editor
    if not f or not f.target then return end
    local summary = self:GetSummary(f.target.guid)
    f.community:SetText(self:ScoreText(summary))
    if summary and summary.at and summary.at > 0 then
        f.freshness:SetText("Checked: " .. self:DateText(summary.at)
            .. (summary.fresh and " (recent online sample)" or " (stale snapshot)"))
    else
        f.freshness:SetText("Checking reachable online reviewers...")
    end
end
function A:OpenEditor(target)
    if not self:ValidateStoredTarget(target) then
        self:Log("Only friendly, same-faction players can be rated.")
        return
    end
    local f = self.editor
    f.target = {guid = target.guid, name = target.name, faction = target.faction, class = target.class}
    local prior = self:GetOwnRating(f.target.guid)
    f.score = (prior and not prior.removed and prior.score) or 0
    f.comment:SetText((prior and not prior.removed and prior.comment) or "")
    f.targetText:SetText(self:DisplayName(f.target.name) .. (f.target.class and ("  •  " .. f.target.class) or ""))
    f.remove:SetEnabled(prior ~= nil and not prior.removed)
    f.save:SetText(prior and not prior.removed and "Update Rating" or "Save Rating")
    self:UpdateEditorStars()
    self:UpdateEditorSummary()
    f:Show()
    self:MarkWindowShown(f)
    self:Query(f.target)
end

function A:CreateReviewsWindow()
    local f = makeFrame("RateMeReviewsWindow", 650, 550)
    label(f, "GameFontNormalLarge", "Rate Me! — Community Reviews", 24, -25)
    f.targetText = label(f, "GameFontHighlight", "", 26, -68, 570)
    f.ratingText = label(f, "GameFontNormal", "", 26, -94, 572)
    f.status = label(f, "GameFontDisableSmall", "", 26, -118, 572)
    f.scroller = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroller:SetPoint("TOPLEFT", 26, -158)
    f.scroller:SetPoint("BOTTOMRIGHT", -48, 65)
    f.content = CreateFrame("Frame", nil, f.scroller)
    f.content:SetSize(562, 1)
    f.scroller:SetScrollChild(f.content)
    f.rows = {}
    f.refresh = button(f, "Refresh", 130, 26, 28, -508, function()
        if f.target then A:Query(f.target, true) end
    end)
    f.comments = button(f, "Fetch Comments", 143, 26, 168, -508, function()
        if f.target then A:RequestComments(f.target.guid); A:DrawReviews() end
    end)
    button(f, "Rate Player", 145, 26, 324, -508, function()
        if f.target then A:OpenEditor(f.target) end
    end)
    self.reviews = f
end

function A:CreateReviewRow(index)
    local f = self.reviews
    local y = -(index - 1) * 117
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(560, 111)
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    local tex = row:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0.18, 0.20, 0.28, index % 2 == 0 and 0.55 or 0.25)
    row.nameText = label(row, "GameFontHighlight", "", 8, -8, 310)
    row.scoreText = label(row, "GameFontNormal", "", 362, -8, 180, "RIGHT")
    row.dateText = label(row, "GameFontDisableSmall", "", 8, -30, 300)
    row.verification = CreateFrame("Button", nil, row)
    row.verification:SetSize(220, 18)
    row.verification:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -27)
    row.verificationText = row.verification:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.verificationText:SetAllPoints()
    row.verificationText:SetJustifyH("RIGHT")
    row.verification:SetScript("OnEnter", function(self)
        if not row.vote then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if A:IsCommunityReviewVerified(row.vote) then
            GameTooltip:AddLine("Verified author", 0.35, 1, 0.45)
            GameTooltip:AddLine("This rating was received directly from its author.", 1, 1, 1, true)
            GameTooltip:AddLine("Last verified: " .. A:DateText(row.vote.verifiedAt), 1, 1, 1, true)
            GameTooltip:AddLine("Verified identifies the source; it does not mean the review is accurate or up to date.", 0.8, 0.8, 0.8, true)
        elseif row.reviewer == A:Key(A.myName) then
            GameTooltip:AddLine("Your review", 1, 0.82, 0)
            GameTooltip:AddLine("You authored this rating on the current character.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Unverified author", 1, 0.75, 0.3)
            GameTooltip:AddLine("This copy has not been received directly from its author.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.verification:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.commentText = label(row, "GameFontHighlightSmall", "", 8, -49, 530)
    row.commentText:SetJustifyV("TOP")
    row.commentText:SetHeight(31)
    row.visibility = button(row, "Show", 83, 20, 266, -85, function()
        if not row.reviewer or not row.vote or not row.vote.comment or A.db.ignored[row.reviewer] then return end
        A:CycleReviewVisibility(f.target.guid, row.reviewer, row.vote)
    end)
    row.block = button(row, "Block", 89, 20, 356, -85, function()
        if not row.reviewer then return end
        A:ToggleReviewerBlock(row.reviewer)
        A:DrawReviews()
    end)
    row.report = button(row, "Report", 90, 20, 452, -85, function()
        if row.reviewer and row.vote and f.target then
            A:OpenReportHelp(row.reviewer, f.target, row.vote)
        end
    end)
    f.rows[index] = row
    return row
end

function A:DrawReviews()
    local f = self.reviews
    if not f or not f.target then return end
    local guid = f.target.guid
    local summary = self:GetSummary(guid)
    f.targetText:SetText(self:DisplayName(f.target.name))
    f.ratingText:SetText(self:ScoreText(summary))
    if summary and summary.count > 0 then
        f.status:SetText(string.format("%d recently verified / %d cached; refresh to check for updates",
            summary.freshCount or 0, summary.cachedCount or summary.count))
    else
        f.status:SetText("No saved reviews; refresh to reach online reviewers")
    end
    local cache = self.runtime.cache[guid]
    local list = {}
    if cache and cache.votes then
        for reviewer, vote in pairs(cache.votes) do
            list[#list + 1] = {reviewer = reviewer, vote = vote}
        end
    end
    table.sort(list, function(a, b)
        if a.vote.date ~= b.vote.date then return a.vote.date > b.vote.date end
        return a.reviewer < b.reviewer
    end)
    for index, entry in ipairs(list) do
        local row = f.rows[index] or self:CreateReviewRow(index)
        local vote = entry.vote
        row.reviewer, row.vote = entry.reviewer, vote
        local ignored = self.db.ignored[entry.reviewer]
        row.nameText:SetText(self:DisplayName(vote.sender or entry.reviewer))
        row.block:SetText(ignored and "Unblock" or "Block")
        row.scoreText:SetText(self:WindowScoreText(vote.score, 15))
        row.dateText:SetText("Rated " .. self:DateText(vote.date))
        if self:IsCommunityReviewVerified(vote) then
            row.verificationText:SetText("Verified author")
            row.verificationText:SetTextColor(0.35, 1, 0.45)
        elseif entry.reviewer == self:Key(self.myName) then
            row.verificationText:SetText("Your review")
            row.verificationText:SetTextColor(1, 0.82, 0)
        else
            row.verificationText:SetText("Unverified author")
            row.verificationText:SetTextColor(1, 0.75, 0.3)
        end

        local commentText, action = self:ReviewCommentText(guid, entry.reviewer, vote)
        row.commentText:SetText(commentText)
        row.visibility:SetText(action or "Show")
        row.visibility:SetEnabled(not ignored and action ~= nil)
        row.report:SetEnabled(self:GetCommentReportEvidence(guid, entry.reviewer, vote) ~= nil)
        row:Show()
    end
    for index = #list + 1, #f.rows do f.rows[index]:Hide() end
    f.content:SetHeight(math.max(1, #list * 117))
end

-- A report refers to the *logged comment sender*, NEVER the reviewed target.
-- This is a manual Blizzard Support workflow; no ticket is submitted by addon.
function A:CreateReportHelpWindow()
    local f = makeFrame("RateMeReportHelpWindow", 585, 480)
    label(f, "GameFontNormalLarge", "Rate Me! — Report Review Author", 22, -25, 535)
    label(f, "GameFontHighlightSmall",
        "This does not submit a report. Report the comment AUTHOR below, not the player being reviewed. " ..
        "Include the exact logged message and a screenshot with your Blizzard Support ticket.",
        26, -65, 530):SetHeight(50)
    label(f, "GameFontNormal", "PLAYER TO REPORT (verified logged sender / Character-Realm):", 26, -127, 535)
    f.author = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.author:SetSize(505, 25)
    f.author:SetPoint("TOPLEFT", 34, -151)
    f.author:SetAutoFocus(false)
    f.author:SetMaxLetters(80)
    f.author:SetScript("OnEscapePressed", function(self) self:ClearFocus(); A:CloseTopWindow() end)
    f.author:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.context = label(f, "GameFontHighlightSmall", "", 26, -191, 535)
    f.context:SetHeight(45)
    label(f, "GameFontNormal", "Exact received logged message (select and copy):", 26, -247, 530)
    f.payload = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.payload:SetSize(505, 67)
    f.payload:SetPoint("TOPLEFT", 34, -272)
    f.payload:SetMultiLine(true)
    f.payload:SetAutoFocus(false)
    f.payload:SetMaxLetters(255)
    f.payload:SetScript("OnEscapePressed", function(self) self:ClearFocus(); A:CloseTopWindow() end)
    f.payload:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    label(f, "GameFontNormal", "Blizzard Support — Harassment in Addon Text:", 26, -354, 530)
    f.url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.url:SetSize(505, 24)
    f.url:SetPoint("TOPLEFT", 34, -378)
    f.url:SetAutoFocus(false)
    f.url:SetMaxLetters(255)
    f.url:SetText("https://battle.net/support/help/product/wow/197/1501/solution")
    f.url:SetScript("OnEscapePressed", function(self) self:ClearFocus(); A:CloseTopWindow() end)
    f.url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    label(f, "GameFontDisableSmall",
        "Copy the author exactly, including realm. Blizzard determines whether a violation occurred.",
        26, -417, 530):SetHeight(27)
    button(f, "Close", 100, 25, 452, -444, function() f:Hide() end)
    self.reportHelp = f
end

function A:OpenReportHelp(reviewer, target, vote)
    if not self.reportHelp or not target then return end
    local evidence = self:GetCommentReportEvidence(target.guid, reviewer, vote)
    if not evidence then return end
    local f = self.reportHelp
    -- Preserve the canonical identity, with its dash, for Blizzard Support.
    -- DisplayName() is intentionally NOT used for report attribution.
    f.author:SetText(evidence.author)
    f.context:SetText(string.format("Reviewed player (context ONLY): %s\nLogged message received: %s (client local time)",
        tostring(target.name or "Unknown"), self:DateText(evidence.receivedAt, true)))
    f.payload:SetText(evidence.payload)
    f:Show()
    self:MarkWindowShown(f)
end

function A:OpenReviews(target)
    if not self:ValidateStoredTarget(target) then return end
    local f = self.reviews
    f.target = {guid = target.guid, name = target.name, faction = target.faction, class = target.class}
    self:RememberTarget(f.target)
    -- A previous reveal is never carried over to a newly opened reviews window.
    self.revealedReviews = {}
    self:Query(f.target)
    f:Show()
    self:MarkWindowShown(f)
    self:RequestComments(f.target.guid)
    self:DrawReviews()
end

function A:ToggleMain()
    if self.main:IsShown() then self.main:Hide() else self.main:Show() end
end

-- Position the star on an orbit around the minimap; angle is persistent SavedVariables data.
function A:PositionMinimapButton()
    local mini = self.minimap
    if not mini or not Minimap then return end
    local angle = math.rad(self.db.settings.minimapAngle or 45)
    local width = Minimap:GetWidth() or 140
    local height = Minimap:GetHeight() or 140
    local radius = math.max(25, math.min(width, height) / 2 + 10)
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Lua 5.1 does not universally provide atan2 (WoW supplies it on many clients).
local function angleFromPoint(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function A:DragMinimapButtonToCursor()
    if not Minimap or not GetCursorPosition then return end
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    if not cursorX or not cursorY or not centerX or not centerY or not scale or scale <= 0 then return end
    local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
    if dx * dx + dy * dy < 9 then return end
    self:SetSetting("minimapAngle", (math.deg(angleFromPoint(dy, dx)) + 360) % 360)
    self:PositionMinimapButton()
end

function A:SetMinimapVisible(visible)
    visible = visible and true or false
    self:SetSetting("minimapVisible", visible)
    if self.minimap then self.minimap:SetShown(visible) end
end

-- Single batch editor for members of the party that just ended. Never writes
-- unchanged existing reviews, and never submits unrated rows.
function A:CreatePartyReviewWindow()
    local f = makeFrame("RateMePartyReviewWindow", 748, 568)
    label(f, "GameFontNormalLarge", "Rate Me! - Rate Your Party", 24, -22)
    label(f, "GameFontHighlightSmall",
        "Choose stars and optionally add comments. Leave a player unrated to skip them.",
        25, -54, 680)
    f.status = label(f, "GameFontDisableSmall", "", 25, -79, 690)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -110)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -47, 64)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(662, 1)
    f.scroll:SetScrollChild(f.content)
    f.rows = {}

    f.save = button(f, "Save Ratings", 155, 27, 390, -522, function()
        local saved, failed, incomplete = 0, 0, 0
        for _, row in ipairs(f.rows) do
            if row:IsShown() and row.target and row.dirty then
                if row.score > 0 then
                    local ok, err = A:SaveOwnRating(row.target, row.score, row.comment:GetText())
                    if ok then
                        saved = saved + 1
                        -- A partial save must not resubmit already-saved reviews.
                        row.initialScore = row.score
                        row.initialComment = row.comment:GetText()
                        row.dirty = false
                    else
                        failed = failed + 1
                        A:Debug("Could not save a party rating: " .. tostring(err))
                    end
                elseif row.comment:GetText() ~= "" then
                    incomplete = incomplete + 1
                end
            end
        end
        if failed > 0 or incomplete > 0 then
            f.status:SetText(string.format("%d saved; %d failed; %d comment(s) need a star rating.",
                saved, failed, incomplete))
        else
            f:Hide()
            A:Log(string.format("Saved %d party rating%s.", saved, saved == 1 and "" or "s"))
        end
    end)
    button(f, "Not Now", 135, 27, 559, -522, function() f:Hide() end)
    self.partyReview = f
end

function A:CreatePartyReviewRow(index)
    local f = self.partyReview
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(660, 92)
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * 95)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(row)
    background:SetColorTexture(0.18, 0.20, 0.25, index % 2 == 0 and 1 or 0.78)
    row.nameText = label(row, "GameFontHighlight", "", 12, -8, 235)
    row.communityText = label(row, "GameFontDisableSmall", "", 12, -29, 245)
    row.stars = {}
    row.score = 0
    row.initialScore = 0
    row.initialComment = ""
    row.dirty = false
    for n = 1, 5 do
        local star = CreateFrame("Button", nil, row)
        star:SetSize(34, 32)
        star:SetPoint("TOPLEFT", row, "TOPLEFT", 270 + (n - 1) * 42, -7)
        local texture = star:CreateTexture(nil, "ARTWORK")
        texture:SetSize(26, 26)
        texture:SetPoint("CENTER")
        texture:SetTexture(self.STAR_EMPTY_TEXTURE)
        star.icon = texture
        star:SetScript("OnClick", function()
            row.score = n
            A:UpdatePartyReviewRow(row)
        end)
        row.stars[n] = star
    end
    row.numeric = label(row, "GameFontHighlight", "", 493, -15, 125, "RIGHT")
    label(row, "GameFontDisableSmall", "Comment:", 12, -62, 68)
    row.comment = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.comment:SetSize(533, 26)
    row.comment:SetPoint("TOPLEFT", row, "TOPLEFT", 90, -51)
    row.comment:SetAutoFocus(false)
    row.comment:SetMaxLetters(self.MAX_COMMENT)
    row.comment:SetScript("OnTextChanged", function()
        if not row.loading then A:UpdatePartyReviewRow(row) end
    end)
    row.comment:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        A:CloseTopWindow()
    end)
    f.rows[index] = row
    return row
end

function A:UpdatePartyReviewRow(row)
    for n, star in ipairs(row.stars) do
        star.icon:SetTexture(n <= row.score and self.STAR_FULL_TEXTURE or self.STAR_EMPTY_TEXTURE)
    end
    row.numeric:SetText(row.score > 0 and string.format("%.1f", row.score) or "Not rated")
    row.dirty = row.score ~= row.initialScore or row.comment:GetText() ~= row.initialComment
end

function A:OpenPartyReview(members)
    if not self.partyReview or type(members) ~= "table" or #members == 0 then return end
    local f = self.partyReview
    f.members = members
    local count = 0
    for _, target in ipairs(members) do
        if self:ValidateStoredTarget(target) then
            count = count + 1
            local row = f.rows[count] or self:CreatePartyReviewRow(count)
            row.target = target
            local prior = self:GetOwnRating(target.guid)
            local hasPrior = prior and not prior.removed
            row.initialScore = hasPrior and prior.score or 0
            row.initialComment = hasPrior and prior.comment or ""
            row.score = row.initialScore
            row.loading = true
            row.comment:SetText(row.initialComment)
            row.loading = false
            row.nameText:SetText(self:DisplayName(target.name))
            local community = self:GetSummary(target.guid)
            if community and community.count and community.count > 0 then
                row.communityText:SetText("Community: " .. self:WindowScoreText(community.average, 11)
                    .. " (" .. community.count .. ")" .. (community.fresh and "" or " [cached]"))
            else
                row.communityText:SetText("Community: no ratings available")
            end
            self:UpdatePartyReviewRow(row)
            row:Show()
        end
    end
    for i = count + 1, #f.rows do f.rows[i]:Hide() end
    if count == 0 then return end
    f.content:SetHeight(math.max(1, count * 95))
    f.status:SetText(string.format("%d eligible player%s from your last party", count, count == 1 and "" or "s"))
    f:Show()
    self:MarkWindowShown(f)
    self:ArrangeWindows()
end

function A:InitializeUI()
    self:CreateMainWindow()
    self:CreateSettingsPanel()
    self:CreateEditorWindow()
    self:CreateReviewsWindow()
    self:CreatePartyReviewWindow()
    self:CreateReportHelpWindow()
    local layoutWatcher = CreateFrame("Frame")
    layoutWatcher:RegisterEvent("UI_SCALE_CHANGED")
    layoutWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    layoutWatcher:SetScript("OnEvent", function() A:ArrangeWindows() end)
    self.layoutWatcher = layoutWatcher
    -- No square dialog backdrop: the round TGA has transparent corners, a
    -- dark circular centre, and a subtle metallic rim at every UI scale.
    -- The familiar bundled star stays independent of the circular background.
    local mini = CreateFrame("Button", "RateMeMinimapButton", Minimap)
    mini:SetSize(32, 32)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    local disc = mini:CreateTexture(nil, "BACKGROUND")
    disc:SetAllPoints(mini)
    disc:SetTexture("Interface\\AddOns\\RateMe\\Media\\MinimapCircle.tga")
    mini.backgroundTexture = disc
    local icon = mini:CreateTexture(nil, "ARTWORK")
    icon:SetSize(25, 25)
    icon:SetPoint("CENTER", mini, "CENTER", 0, 0)
    icon:SetTexture(self.STAR_FULL_TEXTURE)
    mini.starTexture = icon

    mini:RegisterForDrag("LeftButton")
    mini:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function() A:DragMinimapButtonToCursor() end)
        A:DragMinimapButtonToCursor()
    end)
    mini:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        A:DragMinimapButtonToCursor()
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        self.lastDragEnd = GetTime()
    end)
    mini:SetScript("OnClick", function(self, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        -- A released drag must not also open/close the window on some clients.
        if self.dragging or (self.lastDragEnd and GetTime() - self.lastDragEnd < 0.25) then return end
        A:ToggleMain()
    end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Rate Me!", unpack(GOLD))
        GameTooltip:AddLine("Left-click: open ratings", unpack(WHITE))
        GameTooltip:AddLine("Left-drag: move button", unpack(WHITE))
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimap = mini
    self:PositionMinimapButton()
    self:SetMinimapVisible(self.db.settings.minimapVisible)
end
