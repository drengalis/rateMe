local _, A = ...
local GOLD = {1, 0.72, 0.28}
local WHITE = {0.93, 0.91, 0.86}
local MUTED = {0.60, 0.64, 0.70}

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

function A:DateText(timestamp)
    if type(timestamp) ~= "number" or timestamp <= 0 then return "Unknown" end
    return date("%Y-%m-%d", timestamp)
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
    label(f, "GameFontNormalLarge", "Rate Me!", 26, -24)
    label(f, "GameFontDisableSmall", "Player reputation", 145, -29)
    f.tab = "mine"
    f.tabMine = button(f, "My Ratings", 145, 27, 26, -58, function()
        f.tab = "mine"; A:DrawMain()
    end)
    f.tabRecent = button(f, "Recent Lookups", 145, 27, 177, -58, function()
        f.tab = "recent"; A:DrawMain()
    end)
    f.tabSettings = button(f, "Settings", 145, 27, 328, -58, function()
        f.tab = "settings"; A:DrawMain()
    end)
    f.searchLabel = label(f, "GameFontNormalSmall", "Search:", 30, -102)
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(230, 23)
    f.search:SetPoint("TOPLEFT", 85, -94)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(70)
    f.search:SetScript("OnTextChanged", function() A:DrawMain() end)
    f.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        A:CloseTopWindow()
    end)
    f.status = label(f, "GameFontDisableSmall", "", 435, -103, 295, "RIGHT")
    -- Static column headings only: date-descending is now the sole sort order.
    f.playerHeading = label(f, "GameFontNormalSmall", "Player", 30, -135, 213, "RIGHT")
    f.ratingHeading = label(f, "GameFontNormalSmall", "Rating", 253, -135, 157, "RIGHT")
    f.dateHeading = label(f, "GameFontNormalSmall", "Date rated", 418, -135, 237, "RIGHT")
    f.scroller = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroller:SetPoint("TOPLEFT", 29, -164)
    f.scroller:SetPoint("BOTTOMRIGHT", -50, 66)
    f.content = CreateFrame("Frame", nil, f.scroller)
    f.content:SetSize(675, 1)
    f.scroller:SetScrollChild(f.content)
    f.rows = {}
    f.allCharacters = button(f, "Show all my characters", 190, 25, 27, -522, function()
        A.db.settings.allCharacters = not A.db.settings.allCharacters
        A:DrawMain()
    end)
    f.refresh = button(f, "Refresh Selected Target", 170, 25, 567, -522, function()
        if f.selected then
            local target = A.db.recent[f.selected]
            if target then
                A:Query(target, true)
                A:Log("Requested current ratings for " .. A:DisplayName(target.name))
            end
        end
    end)
    f:SetScript("OnShow", function()
        A:MarkWindowShown(f)
        A:DrawMain()
        A:ArrangeWindows()
    end)
    self.main = f
end

function A:CreateSettingsPanel()
    local scroll = CreateFrame("ScrollFrame", nil, self.main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", self.main, "TOPLEFT", 29, -97)
    scroll:SetPoint("BOTTOMRIGHT", self.main, "BOTTOMRIGHT", -38, 50)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(675, 1210)
    scroll:SetScrollChild(p)

    local function checkbox(key, title, y, onClick)
        local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        c:SetSize(30, 30)
        c:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -y)
        label(p, "GameFontHighlight", title, 44, -(y + 7), 590)
        c:SetScript("OnClick", function(self)
            A.db.settings[key] = self:GetChecked() and true or false
            onClick()
            A:DrawSettings()
        end)
        return c
    end
    local function threshold(name, key, y)
        local slider = CreateFrame("Slider", name, p, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", p, "TOPLEFT", 35, -y)
        slider:SetSize(335, 19)
        slider:SetMinMaxValues(1, 5)
        slider:SetValueStep(0.5)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local base = slider:GetName()
        if _G[base .. "Low"] then _G[base .. "Low"]:SetText("1.0") end
        if _G[base .. "High"] then _G[base .. "High"]:SetText("5.0") end
        if _G[base .. "Text"] then _G[base .. "Text"]:SetText("") end
        slider:SetValue(A.db.settings[key])
        slider:SetScript("OnValueChanged", function(self, value)
            local rounded = math.max(1, math.min(5, math.floor(value * 2 + 0.5) / 2))
            if math.abs(value - rounded) > 0.001 then self:SetValue(rounded); return end
            if A.db.settings[key] ~= rounded then
                A.db.settings[key] = rounded
                A:OnAlertSettingsChanged()
            end
            A:DrawSettings()
        end)
        return slider
    end

    label(p, "GameFontNormalLarge", "Group Rating Alerts", 10, -12)
    label(p, "GameFontHighlightSmall", "Warn about low-rated players joining your party or raid.", 10, -42, 650)
    p.enabled = checkbox("lowRatingAlerts", "Enable group join warnings", 75, function() A:OnAlertSettingsChanged() end)
    p.alertPersonal = checkbox("lowRatingPersonal", "Use my personal ratings", 111, function() A:OnAlertSettingsChanged() end)
    p.alertCommunity = checkbox("lowRatingCommunity", "Use community ratings", 148, function() A:OnAlertSettingsChanged() end)

    label(p, "GameFontNormal", "Personal rating warning threshold", 15, -193)
    p.personalThreshold = threshold("RateMePersonalAlertThresholdSlider", "lowRatingPersonalThreshold", 231)
    p.personalThresholdValue = label(p, "GameFontHighlight", "", 421, -228, 220)
    label(p, "GameFontNormal", "Community rating warning threshold", 15, -280)
    p.threshold = threshold("RateMeAlertThresholdSlider", "lowRatingThreshold", 318)
    p.thresholdValue = label(p, "GameFontHighlight", "", 421, -315, 220)
    p.explanation = label(p, "GameFontHighlightSmall", "", 15, -366, 650)
    p.explanation:SetJustifyV("TOP")
    p.explanation:SetHeight(54)

    label(p, "GameFontNormalLarge", "Player Rating Highlights", 10, -438)
    p.highlights = checkbox("ratingHighlights", "Highlight rated friendly players", 470,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightPersonal = checkbox("ratingHighlightsPersonal", "Use my personal ratings", 508,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightCommunity = checkbox("ratingHighlightsCommunity", "Use community ratings", 545,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightExplanation = label(p, "GameFontHighlightSmall", "", 15, -590, 650)
    p.highlightExplanation:SetJustifyV("TOP")
    p.highlightExplanation:SetHeight(64)

    label(p, "GameFontNormalLarge", "Minimap Button", 10, -682)
    p.minimapVisible = checkbox("minimapVisible", "Show Rate Me! minimap button", 713,
        function() A:SetMinimapVisible(A.db.settings.minimapVisible) end)
    label(p, "GameFontHighlightSmall", "Left-click to open. Left-drag to reposition. /rateme always opens the window.", 15, -753, 650)

    label(p, "GameFontNormalLarge", "Post-Party Ratings", 10, -811)
    p.partyReviewPrompt = checkbox("partyReviewPrompt", "Offer to rate party members when I leave a party", 841,
        function() if not A.db.settings.partyReviewPrompt then A.pendingPartyReview = nil end end)
    label(p, "GameFontHighlightSmall",
        "Party only, not raids. Includes friendly players encountered during the party. " ..
        "Use /rateme party to reopen the most recent party.", 15, -885, 640)

    label(p, "GameFontNormalLarge", "Comment Safety", 10, -959)
    p.hideCommentsByDefault = checkbox("hideCommentsByDefault", "Hide written reviews by default", 989, function()
        A.revealedReviews = {} -- new preference applies to all current review rows
        if A.reviews and A.reviews:IsShown() then A:DrawReviews() end
    end)
    label(p, "GameFontHighlightSmall",
        "Written reviews are not profanity-filtered. Use Show/Hide per review, " ..
        "Block to hide a reviewer's comments, or Report for Blizzard support instructions. " ..
        "Comments are sent through logged addon messaging.", 15, -1030, 645)

    -- Existing callers access controls via the scroll frame, not its child.
    for _, name in ipairs({"enabled", "alertPersonal", "alertCommunity", "threshold", "thresholdValue",
        "personalThreshold", "personalThresholdValue", "explanation", "highlights", "highlightPersonal",
        "highlightCommunity", "highlightExplanation", "minimapVisible", "partyReviewPrompt",
        "hideCommentsByDefault"}) do
        scroll[name] = p[name]
    end
    self.main.settingsPanel = scroll
    scroll:Hide()
end

function A:DrawSettings()
    local f = self.main
    if not f or not f.settingsPanel then return end
    local p = f.settingsPanel
    local settings = self.db.settings
    p.enabled:SetChecked(settings.lowRatingAlerts)
    p.alertPersonal:SetChecked(settings.lowRatingPersonal)
    p.alertCommunity:SetChecked(settings.lowRatingCommunity)
    p.highlights:SetChecked(settings.ratingHighlights)
    p.highlightPersonal:SetChecked(settings.ratingHighlightsPersonal)
    p.highlightCommunity:SetChecked(settings.ratingHighlightsCommunity)
    p.minimapVisible:SetChecked(settings.minimapVisible)
    p.partyReviewPrompt:SetChecked(settings.partyReviewPrompt)
    p.hideCommentsByDefault:SetChecked(settings.hideCommentsByDefault)
    p.alertPersonal:SetEnabled(settings.lowRatingAlerts)
    p.alertCommunity:SetEnabled(settings.lowRatingAlerts)
    p.threshold:SetEnabled(settings.lowRatingAlerts and settings.lowRatingCommunity)
    p.personalThreshold:SetEnabled(settings.lowRatingAlerts and settings.lowRatingPersonal)
    p.highlightPersonal:SetEnabled(settings.ratingHighlights)
    p.highlightCommunity:SetEnabled(settings.ratingHighlights)
    if math.abs(p.threshold:GetValue() - settings.lowRatingThreshold) > 0.001 then
        p.threshold:SetValue(settings.lowRatingThreshold)
    end
    if math.abs(p.personalThreshold:GetValue() - settings.lowRatingPersonalThreshold) > 0.001 then
        p.personalThreshold:SetValue(settings.lowRatingPersonalThreshold)
    end
    p.thresholdValue:SetText(string.format("%.1f stars or lower", settings.lowRatingThreshold))
    p.personalThresholdValue:SetText(string.format("%.1f stars or lower", settings.lowRatingPersonalThreshold))
    p.explanation:SetText("Select either or both rating sources. Personal ratings work offline; " ..
        "community ratings need a fresh verified online sample. If either score " ..
        "meets its threshold, show one group warning per player until they leave.")
    p.highlightExplanation:SetText("Gold: 4.0+; red: below 2.0; no glow for 2.0-3.9. " ..
        "Select either or both sources. Red wins if both conflict. " ..
        "Community glows require fresh ratings; personal glows work offline. " ..
        "Visible friendly nameplates outdoors and supported group frames.")
end

function A:CreateMainRow(index)
    local f = self.main
    local b = CreateFrame("Button", nil, f.content)
    b:SetSize(675, 38)
    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * 40)
    local tex = b:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0.19, 0.23, 0.30, index % 2 == 0 and 0.4 or 0.2)
    b.nameText = label(b, "GameFontHighlight", "", 8, -7, 235, "RIGHT")
    b.subText = label(b, "GameFontDisableSmall", "", 8, -23, 235, "RIGHT")
    b.scoreText = label(b, "GameFontNormal", "", 253, -12, 157, "RIGHT")
    b.dateText = label(b, "GameFontHighlightSmall", "", 418, -12, 237, "RIGHT")
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
    f.searchLabel:SetShown(not isSettings)
    f.search:SetShown(not isSettings)
    f.status:SetShown(not isSettings)
    f.scroller:SetShown(not isSettings)
    f.playerHeading:SetShown(not isSettings)
    f.ratingHeading:SetShown(not isSettings)
    f.dateHeading:SetShown(not isSettings)
    f.dateHeading:SetText(f.tab == "recent" and "Last checked" or "Date rated")
    f.allCharacters:SetText(self.db.settings.allCharacters and "All characters: ON" or "All characters: OFF")
    f.allCharacters:SetShown(f.tab == "mine")
    f.refresh:SetShown(f.tab == "recent")
    if isSettings then self:DrawSettings(); return end
    local records = f.tab == "mine" and self:ListOwn() or self:ListRecent()
    local filter = f.search:GetText():lower()
    local items = {}
    for _, record in ipairs(records) do
        if record.name and (filter == "" or record.name:lower():find(filter, 1, true)
            or self:DisplayName(record.name):lower():find(filter, 1, true)) then
            items[#items + 1] = record
        end
    end
    sortItems(items, f.tab == "recent")
    f.status:SetText(tostring(#items) .. " player" .. (#items == 1 and "" or "s"))
    for index, item in ipairs(items) do
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
    for index = #items + 1, #f.rows do f.rows[index]:Hide() end
    f.content:SetHeight(math.max(1, #items * 40))
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
    f.comment = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.comment:SetSize(432, 85)
    f.comment:SetPoint("TOPLEFT", 36, -339)
    f.comment:SetMultiLine(true)
    f.comment:SetMaxLetters(self.MAX_COMMENT)
    f.comment:SetAutoFocus(false)
    if f.comment.SetTextInsets then f.comment:SetTextInsets(6, 6, 6, 6) end
    f.comment:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        A:CloseTopWindow()
    end)
    f.comment:SetScript("OnTextChanged", function(self)
        if f.bytes then f.bytes:SetText(tostring(#self:GetText()) .. " / 160 bytes") end
    end)
    f.bytes = label(f, "GameFontDisableSmall", "", 369, -428, 105, "RIGHT")
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
    row.commentText = label(row, "GameFontHighlightSmall", "", 8, -49, 530)
    row.commentText:SetJustifyV("TOP")
    row.commentText:SetHeight(31)
    row.visibility = button(row, "Show", 83, 20, 266, -85, function()
        if not row.reviewer or not row.vote or not row.vote.comment or A.db.ignored[row.reviewer] then return end
        A:CycleReviewVisibility(f.target.guid, row.reviewer, row.vote)
    end)
    row.block = button(row, "Block", 89, 20, 356, -85, function()
        if not row.reviewer then return end
        A.db.ignored[row.reviewer] = not A.db.ignored[row.reviewer] or nil
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
    f.status:SetText(summary and summary.fresh and "Directly verified responses from the latest query"
        or "Cached result; refresh to reach online reviewers")
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
        tostring(target.name or "Unknown"), date("%Y-%m-%d %H:%M:%S", evidence.receivedAt)))
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
    self.db.settings.minimapAngle = (math.deg(angleFromPoint(dy, dx)) + 360) % 360
    self:PositionMinimapButton()
end

function A:SetMinimapVisible(visible)
    visible = visible and true or false
    self.db.settings.minimapVisible = visible
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
                        A:Debug("Party rating not saved: " .. tostring(err))
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
    local mini = CreateFrame("Button", "RateMeMinimapButton", Minimap, "BackdropTemplate")
    mini:SetSize(29, 29)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    mini:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 14, insets = {left = 3, right = 3, top = 3, bottom = 3}})
    mini:SetBackdropColor(0.10, 0.11, 0.17, 0.94)
    local icon = mini:CreateTexture(nil, "OVERLAY")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", mini, "CENTER", 0, 1)
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
