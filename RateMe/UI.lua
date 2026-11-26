local _, A = ...
local GOLD = {1, 0.72, 0.28}
local WHITE = {0.93, 0.91, 0.86}
local MUTED = {0.60, 0.64, 0.70}
-- Neutral bronze used by the default UI's frame trim, for rules and borders.
local BRONZE = {0.55, 0.45, 0.25}

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

-- Windows use Blizzard's own PortraitFrameTemplate, the same chrome as the
-- Character window: bronze frame, round portrait in the top-left corner (the
-- Rate Me! star), centred title and the standard X close button. Older or
-- unusual clients fall back to BasicFrameTemplate, then to the old dialog look.
local WINDOW_TEMPLATES = {"PortraitFrameTemplate", "BasicFrameTemplate"}

local function setWindowPortrait(f)
    local portrait = (f.PortraitContainer and f.PortraitContainer.portrait)
        or f.portrait or f.Portrait or _G[f:GetName() .. "Portrait"]
    if not portrait then return end
    -- Dark round backing (same art as the minimap button), then the star on top.
    if SetPortraitToTexture then
        SetPortraitToTexture(portrait, "Interface\\AddOns\\RateMe\\Media\\MinimapCircle.tga")
    else
        portrait:SetTexture("Interface\\AddOns\\RateMe\\Media\\MinimapCircle.tga")
    end
    local host = portrait:GetParent() or f
    local star = host:CreateTexture(nil, "OVERLAY", nil, 7)
    star:SetTexture(A.STAR_FULL_TEXTURE)
    local size = (portrait.GetWidth and portrait:GetWidth()) or 60
    if not size or size <= 0 then size = 60 end
    -- The portrait art sits slightly right of and below the visible ring in
    -- this client; nudge the star left and up (about 4% of the portrait) so it
    -- is centred in the circle (measured from in-game screenshots).
    star:SetPoint("CENTER", portrait, "CENTER", -1.5, size * 0.037)
    star:SetSize(size * 0.62, size * 0.62)
    f.portraitStar = star
end

local function makeFrame(name, width, height, title)
    local f
    for _, template in ipairs(WINDOW_TEMPLATES) do
        local ok, created = pcall(CreateFrame, "Frame", name, UIParent, template)
        if ok and created and (created.CloseButton or _G[name .. "CloseButton"]) then
            f = created
            f.rateMeTemplate = template
            break
        elseif ok and created then
            created:Hide()
        end
    end
    if not f then
        f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = false, edgeSize = 28,
            insets = {left = 8, right = 8, top = 8, bottom = 8},
        })
        f:SetBackdropColor(0.04, 0.04, 0.04, 1)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -5, -5)
        f.CloseButton = close
    end
    f.CloseButton = f.CloseButton or _G[name .. "CloseButton"]
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end
    title = title or A.title or "Rate Me!"
    f.TitleText = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
        or _G[name .. "TitleText"]
    if f.SetTitle then
        f:SetTitle(title)
    else
        if not f.TitleText then
            f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.TitleText:SetPoint("TOP", f, "TOP", 0, -6)
        end
        f.TitleText:SetText(title)
    end
    if f.rateMeTemplate == "PortraitFrameTemplate" then setWindowPortrait(f) end
    f:SetSize(width, height)
    f.defaultWidth, f.defaultHeight = width, height
    f:SetPoint("CENTER")
    -- Same layer as the game's own windows (Character, Spellbook, ...), so
    -- bags, the map and Blizzard popups behave normally around Rate Me!.
    -- Top-level windows come to the front when clicked, like the default UI.
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if A.SaveWindowPlacement then A:SaveWindowPlacement(self) end
    end)
    -- Opaque layer beneath the template's (partly transparent) background so
    -- the game world never shows through the window contents.
    local background = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    background:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    background:SetColorTexture(0.04, 0.04, 0.04, 1)
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
        self:Raise()
        if A.MarkWindowShown then A:MarkWindowShown(self) end
        if A.ArrangeWindows then A:ArrangeWindows() end
    end)
    f:SetScript("OnHide", function(self)
        if A.ArrangeWindows then A:ArrangeWindows() end
    end)
    f:Hide()
    return f
end

-- Bottom-right drag grip, the same one the chat windows use. The design size
-- is the minimum, because list columns and controls are laid out for it.
local function makeResizable(f, minWidth, minHeight, maxWidth, maxHeight)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else
        if f.SetMinResize then f:SetMinResize(minWidth, minHeight) end
        if f.SetMaxResize then f:SetMaxResize(maxWidth, maxHeight) end
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if A.SaveWindowPlacement then A:SaveWindowPlacement(f) end
    end)
    f.resizeGrip = grip
    return grip
end

-- Remember where the player put each window (and its size, if resizable), per
-- account in RateMeDB.windows, keyed by the window's frame name. Positions are
-- stored with the window's scale so a restored window lands on the same pixels.
local function windowStore()
    local db = A.db
    if type(db) ~= "table" then return nil end
    if type(db.windows) ~= "table" then db.windows = {} end
    return db.windows
end

function A:SaveWindowPlacement(frame)
    local store = windowStore()
    local name = frame and frame:GetName()
    if not store or not name then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    store[name] = {
        left = left, top = top, scale = frame:GetScale(),
        width = frame:IsResizable() and frame:GetWidth() or nil,
        height = frame:IsResizable() and frame:GetHeight() or nil,
    }
end

-- Returns true when the window has a remembered placement and was restored.
function A:RestoreWindowPlacement(frame)
    local store = windowStore()
    local saved = store and frame and frame:GetName() and store[frame:GetName()]
    if type(saved) ~= "table" or type(saved.left) ~= "number" or type(saved.top) ~= "number" then
        return false
    end
    local scale = tonumber(saved.scale) or 1
    if scale <= 0 then scale = 1 end
    frame:SetScale(scale)
    if frame:IsResizable() and type(saved.width) == "number" and type(saved.height) == "number" then
        frame:SetSize(saved.width, saved.height)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
    return true
end

-- Tile the visible windows into one horizontal row, centred on the screen.
-- Sizes are in UIParent coordinates; a common scale ensures even small screens
-- never put one Rate Me! window on top of another. Windows the player has
-- moved or resized keep their remembered placement and are left out of the row.
function A:ArrangeWindows()
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then return end
    local frames = {}
    local totalWidth, maxHeight = 0, 0
    for _, windowName in ipairs({"main", "editor", "reviews", "partyReview"}) do
        local frame = self[windowName]
        if frame and frame:IsShown() and self:RestoreWindowPlacement(frame) then
            frame = nil
        end
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
    for _, windowName in ipairs({"main", "editor", "reviews", "partyReview"}) do
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
-- Round class icons from the default UI (the same art as unit frames), with
-- built-in coordinates in case the game's CLASS_ICON_TCOORDS table is missing.
local CLASS_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local FALLBACK_CLASS_COORDS = {
    WARRIOR = {0, 0.25, 0, 0.25}, MAGE = {0.25, 0.49609375, 0, 0.25},
    ROGUE = {0.49609375, 0.7421875, 0, 0.25}, DRUID = {0.7421875, 0.98828125, 0, 0.25},
    HUNTER = {0, 0.25, 0.25, 0.5}, SHAMAN = {0.25, 0.49609375, 0.25, 0.5},
    PRIEST = {0.49609375, 0.7421875, 0.25, 0.5}, WARLOCK = {0.7421875, 0.98828125, 0.25, 0.5},
    PALADIN = {0, 0.25, 0.5, 0.75},
}

local function classToken(class)
    if type(class) ~= "string" or class == "" then return nil end
    local token = class:upper():gsub("%s", "")
    if (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]) or FALLBACK_CLASS_COORDS[token] then return token end
    return nil
end

-- Give a name label a round class icon that sits just before the name and
-- shows the class name on mouseover. onClick lets a click on the icon still
-- act on the row it belongs to.
function A:AttachClassIcon(fs, parent, onClick)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(16, 16)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexture(CLASS_ICON_TEXTURE)
    -- Thin black outline: the same round class art, tinted black and drawn
    -- 1px larger all round behind the icon.
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetTexture(CLASS_ICON_TEXTURE)
    icon.border:SetSize(18, 18)
    icon.border:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.border:SetVertexColor(0, 0, 0)
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if not self.className then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.token]
        if color then GameTooltip:AddLine(self.className, color.r, color.g, color.b)
        else GameTooltip:AddLine(self.className, 1, 1, 1) end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if onClick then icon:SetScript("OnMouseUp", function() onClick() end) end
    icon:Hide()
    fs.classIcon = icon
    fs.classIconParent = parent
    return icon
end

local function className(token)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token])
        or (token:sub(1, 1) .. token:sub(2):lower())
end

-- Put "<class icon> text" on a label made with AttachClassIcon. The icon sits
-- just before the visible text whatever the label's alignment: left-aligned
-- labels move right to make room, centred labels move right by half so the
-- icon and text stay centred together, and right-aligned labels stay put.
-- x, y are the label's normal TOPLEFT offsets on its parent.
local ICON_SPACE = 22 -- icon plus gap
function A:SetIconLabel(fs, text, class, x, y)
    fs:SetText(text)
    local icon, token = fs.classIcon, classToken(class)
    local justify = fs.justify or (fs.GetJustifyH and fs:GetJustifyH()) or "CENTER"
    local shift = 0
    if token and justify == "LEFT" then shift = ICON_SPACE
    elseif token and justify == "CENTER" then shift = ICON_SPACE / 2 end
    if x and y then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", fs.classIconParent, "TOPLEFT", x + shift, y)
    end
    if not icon then return end
    if not token then icon:Hide(); icon.className = nil; return end
    local coords = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]) or FALLBACK_CLASS_COORDS[token]
    icon.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    icon.border:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    icon.token = token
    icon.className = className(token)
    icon:ClearAllPoints()
    local width = fs.GetStringWidth and fs:GetStringWidth() or 0
    if justify == "LEFT" then
        icon:SetPoint("RIGHT", fs, "LEFT", -6, 0)
    elseif justify == "RIGHT" then
        icon:SetPoint("RIGHT", fs, "RIGHT", -(width + 6), 0)
    else
        icon:SetPoint("RIGHT", fs, "CENTER", -(width / 2 + 6), 0)
    end
    icon:Show()
end

-- "<class icon> Name" wherever a player's name and class are shown together.
function A:SetPlayerLabel(fs, name, class, x, y)
    self:SetIconLabel(fs, self:DisplayName(name), class, x, y)
end

-- "<class icon> Class name" on its own line; empty when the class is unknown.
function A:SetClassLabel(fs, class, x, y)
    local token = classToken(class)
    self:SetIconLabel(fs, token and className(token) or "", class, x, y)
end

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
    return self:StarMarkup(value, size) .. " " .. self:RatingNumberText(roundedTenth)
end

-- "N unverified, not counted" for reviews left out of the average.
function A:UnverifiedText(summary)
    local n = summary and summary.unverifiedCount or 0
    if n <= 0 then return nil end
    return string.format("%d unverified, not counted", n)
end

function A:ScoreText(summary)
    local unverified = self:UnverifiedText(summary)
    if not summary or not summary.average or summary.count == 0 then
        if unverified then return "No verified ratings  \194\183  " .. unverified end
        return "No ratings available"
    end
    local text = self:WindowScoreText(summary.average, 15) .. string.format("  (%d verified rating%s)",
        summary.count, summary.count == 1 and "" or "s")
    if not summary.fresh then text = text .. "  [cached]" end
    if unverified then text = text .. "  \194\183  " .. unverified end
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
    local MAIN_WIDTH, MAIN_HEIGHT = 770, 565
    local f = makeFrame("RateMeMainWindow", MAIN_WIDTH, MAIN_HEIGHT, "Rate Me!")
    makeResizable(f, MAIN_WIDTH, 420, 1400, 1000)
    -- The window title lives in the Blizzard titlebar. Below it, one header
    -- row holds the tagline (left) and the navigation tabs (right-aligned, so
    -- they stay at the right edge when the window is resized).
    -- x = 66 keeps the tagline clear of the round portrait in the top-left corner.
    f.tagline = label(f, "GameFontDisableSmall", "Reputation earned. Reputation shared.", 66, -48, 195, "LEFT")
    f.tab = "mine"
    f.pages = {mine = 1, recent = 1, grouped = 1}
    f.tabMine = button(f, "My Ratings", 107, 27, 370, -38, function()
        f.tab = "mine"; f.selected = nil; A:DrawMain()
    end)
    f.tabRecent = button(f, "Recent Lookups", 132, 27, 482, -38, function()
        f.tab = "recent"; f.selected = nil; A:DrawMain()
    end)
    f.tabGrouped = button(f, "Recent Players", 122, 27, 0, -38, function()
        f.tab = "grouped"; f.selected = nil; A:DrawMain()
    end)
    f.tabSettings = button(f, "Settings", 98, 27, 619, -38, function()
        f.tab = "settings"; f.selected = nil; A:DrawMain()
    end)
    f.tabSettings:ClearAllPoints()
    -- The X now sits in the titlebar, so the tabs line up with the dividers.
    f.tabSettings:SetPoint("TOPRIGHT", f, "TOPRIGHT", -29, -38)
    f.tabGrouped:ClearAllPoints()
    f.tabGrouped:SetPoint("TOPRIGHT", f.tabSettings, "TOPLEFT", -5, 0)
    f.tabRecent:ClearAllPoints()
    f.tabRecent:SetPoint("TOPRIGHT", f.tabGrouped, "TOPLEFT", -5, 0)
    f.tabMine:ClearAllPoints()
    f.tabMine:SetPoint("TOPRIGHT", f.tabRecent, "TOPLEFT", -5, 0)
    -- Keep the title/navigation, list, and pagination/search visually distinct
    -- without adding extra headers or taking space away from the scroll area.
    -- Plain colour textures are supported by Forever's client and scale with
    -- the window, unlike fixed-width decorative character glyphs.
    local function divider(y)
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.9)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 29, y)
        line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -29, y)
        return line
    end
    f.headerDivider = divider(-81)
    -- A fine line also fixes the column headings visually above scrolling rows.
    f.listHeadingDivider = f:CreateTexture(nil, "ARTWORK")
    f.listHeadingDivider:SetHeight(1)
    f.listHeadingDivider:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.6)
    f.listHeadingDivider:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_VIEWPORT_X, -117)
    f.listHeadingDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -117)
    -- Pagination belongs to the results area. Put the divider *below* its
    -- controls, then use the darker footer only for Search and Clear.
    f.footerBackground = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.footerBackground:SetColorTexture(0, 0, 0, 0.35)
    -- Footer and pager are anchored to the bottom edge so they follow resizing.
    -- Offsets are the original top-based positions converted for MAIN_HEIGHT.
    f.footerBackground:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 25, MAIN_HEIGHT - 506)
    f.footerBackground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -25, 12)
    f.footerDivider = divider(-506)
    f.footerDivider:ClearAllPoints()
    f.footerDivider:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 29, MAIN_HEIGHT - 506)
    f.footerDivider:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -29, MAIN_HEIGHT - 506)
    -- Search is the only footer control. All Characters lives in Settings,
    -- and lookup refresh remains in the selected player's drilldown window.
    -- Player counts sit right-aligned on the same row as the pager instead of
    -- floating in the blank space above the column headings.
    f.status = label(f, "GameFontDisableSmall", "", 588, -477, 153, "RIGHT")
    f.status:ClearAllPoints()
    f.status:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -29, MAIN_HEIGHT - 477)
    f.searchLabel = label(f, "GameFontNormalSmall", "Search:", 29, -526)
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(400, 23)
    f.search:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 72, MAIN_HEIGHT - 520)
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
    -- Shown in the list area when a tab has no players, or the search has no matches.
    f.emptyText = label(f, "GameFontDisable", "", 0, 0, 500, "CENTER")
    f.emptyText:ClearAllPoints()
    f.emptyText:SetPoint("TOP", f.scroller, "TOP", 0, -40)
    f.emptyText:Hide()
    f.previousPage = button(f, "Previous", 95, 24, 244, -471, function()
        if not f.pages[f.tab] then return end
        local page = f.pages[f.tab] or 1
        if page <= 1 then return end
        f.pages[f.tab] = page - 1
        f.selected = nil
        A:DrawMain()
    end)
    f.pageIndicator = label(f, "GameFontHighlightSmall", "Page 1 of 1", 349, -477, 123, "CENTER")
    -- Keep the pager group together, centred where it was relative to the window.
    f.pageIndicator:ClearAllPoints()
    f.pageIndicator:SetPoint("TOP", f, "BOTTOM", 349 + 123 / 2 - MAIN_WIDTH / 2, MAIN_HEIGHT - 477)
    f.previousPage:ClearAllPoints()
    f.previousPage:SetPoint("TOPRIGHT", f.pageIndicator, "TOPLEFT", -10, 6)
    f.nextPage = button(f, "Next", 95, 24, 484, -471, function()
        if not f.pages[f.tab] then return end
        local page = f.pages[f.tab] or 1
        if page >= (f.pageCounts and f.pageCounts[f.tab] or 1) then return end
        f.pages[f.tab] = page + 1
        f.selected = nil
        A:DrawMain()
    end)
    f.nextPage:ClearAllPoints()
    f.nextPage:SetPoint("TOPLEFT", f.pageIndicator, "TOPRIGHT", 12, 6)
    f:SetScript("OnShow", function()
        f:Raise()
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
    p:SetSize(699, 1624) -- eight responsive sections, including communication and reset
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
        card:SetBackdropColor(0.07, 0.065, 0.06, 1) -- opaque, neutral dark
        card:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1)
        -- A previous 3px gold accent rendered as a stray glyph beside headings
        -- on Forever. Keep the gold heading without that decorative bar.
        local titleText = label(card, "GameFontNormalLarge", title, 20, -12)
        titleText:SetTextColor(unpack(GOLD))
        return card
    end

    local function rule(card, y)
        local tex = card:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.7)
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

    local myRatings = section(12, 125, "My Ratings")
    p.allCharacters, p.allCharactersRow, p.allCharactersLabel = checkbox(myRatings,
        "allCharacters", "Show ratings from all my characters in My Ratings", 19, 51,
        function()
            -- This changes only which saved personal records are shown.
            -- Keep per-character authorship and existing records untouched.
            self.main.pages.mine = 1
            self.main.selected = nil
        end)
    p.confirmRemoveRating, p.confirmRemoveRatingRow, p.confirmRemoveRatingLabel = checkbox(myRatings,
        "confirmRemoveRating", "Ask for confirmation before removing one of my ratings", 19, 86)

    local alerts = section(156, 345, "Group Rating Alerts")
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

    local highlights = section(520, 323, "Player Rating Highlights")
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
    p.highlightChat, p.highlightChatRow, p.highlightChatLabel = checkbox(highlights,
        "ratingHighlightsChat", "Show a star with the rating before chat messages", 43, 170)
    rule(highlights, 207)
    p.highlightPersonal, p.highlightPersonalRow, p.highlightPersonalLabel = checkbox(highlights,
        "ratingHighlightsPersonal", "Use ratings I personally gave players", 43, 217,
        function() A:OnHighlightSettingsChanged() end)
    p.highlightCommunity, p.highlightCommunityRow, p.highlightCommunityLabel = checkbox(highlights,
        "ratingHighlightsCommunity", "Use recent verified community ratings", 43, 252,
        function() A:OnHighlightSettingsChanged() end)
    local legend = label(highlights, "GameFontHighlightSmall",
        "Stars: community first, then personal.  Gold: 4.0+   Red: below 2.0", 47, -296, 610)
    legend:SetTextColor(unpack(MUTED))

    local party = section(862, 109, "Post-Party Ratings")
    p.partyReviewPrompt, p.partyReviewPromptRow, p.partyReviewPromptLabel = checkbox(party,
        "partyReviewPrompt", "Open the party rating popup when I leave a party", 19, 51,
        function() if not A.db.settings.partyReviewPrompt then A.pendingPartyReview = nil end end)
    local partyHint = label(party, "GameFontHighlightSmall",
        "Dismiss with Escape. Reopen the last party with /rateme party.", 55, -84, 545)
    partyHint:SetTextColor(unpack(MUTED))

    local minimap = section(990, 109, "Minimap Button")
    p.minimapVisible, p.minimapVisibleRow, p.minimapVisibleLabel = checkbox(minimap,
        "minimapVisible", "Show the movable Rate Me! button on my minimap", 19, 51,
        function() A:SetMinimapVisible(A.db.settings.minimapVisible) end)
    local miniHint = label(minimap, "GameFontHighlightSmall",
        "Left-click: open     Left-drag: move     /rateme: always available", 55, -84, 545)
    miniHint:SetTextColor(unpack(MUTED))

    local communication = section(1118, 267, "Communication")
    p.sendRatingBroadcasts = checkbox(communication, "sendRatingBroadcasts",
        "Announce my new, edited and removed ratings to other users", 19, 42,
        function() A:OnCommunicationSettingsChanged() end)
    p.receiveRatingBroadcasts = checkbox(communication, "receiveRatingBroadcasts",
        "Receive and save rating announcements from other users", 19, 77,
        function() A:OnCommunicationSettingsChanged() end)
    -- Hovering over a player only asks other users when this is on.
    p.lookupOnHover = checkbox(communication, "lookupOnHover",
        "Look up community ratings when I hover over players", 19, 112)
    -- A divider keeps the unrelated peer-count slider apart from the checkboxes.
    p.communicationRule = rule(communication, 152)
    label(communication, "GameFontHighlightSmall", "Maximum direct peers per lookup", 55, -167, 390)
    p.lookupPeerValue = label(communication, "GameFontNormal", "", 460, -167, 150, "RIGHT")
    p.lookupPeerCount = CreateFrame("Slider", "RateMeLookupPeerCount", communication, "OptionsSliderTemplate")
    p.lookupPeerCount:SetPoint("TOPLEFT", communication, "TOPLEFT", 61, -195)
    p.lookupPeerCount:SetSize(340, 19)
    p.lookupPeerCount:SetMinMaxValues(1, 20)
    p.lookupPeerCount:SetValueStep(1)
    if p.lookupPeerCount.SetObeyStepOnDrag then p.lookupPeerCount:SetObeyStepOnDrag(true) end
    local sliderName = p.lookupPeerCount:GetName()
    if sliderName then
        if _G[sliderName .. "Low"] then _G[sliderName .. "Low"]:SetText("1") end
        if _G[sliderName .. "High"] then _G[sliderName .. "High"]:SetText("20") end
        if _G[sliderName .. "Text"] then _G[sliderName .. "Text"]:SetText("") end
    end
    p.lookupPeerCount:SetScript("OnValueChanged", function(self, value)
        local rounded = math.max(1, math.min(20, math.floor(value + 0.5)))
        if math.abs(value - rounded) > 0.001 then self:SetValue(rounded); return end
        if A.db.settings.lookupPeerCount ~= rounded then A:SetSetting("lookupPeerCount", rounded) end
        p.lookupPeerValue:SetText(tostring(rounded))
    end)
    local networkHint = label(communication, "GameFontDisableSmall",
        "Peers may forward lookups. Broadcast reach depends on available game channels.", 55, -237, 580)

    local diagnostics = section(1405, 90, "Diagnostics")
    p.debug, p.debugRow, p.debugLabel = checkbox(diagnostics,
        "debug", "Show rating and peer-to-peer activity in chat (debug)", 19, 51)

    local reset = section(1515, 98, "Reset")
    p.resetDefaults = button(reset, "Reset to Default", 160, 26, 19, -46, function()
        A:ConfirmResetToDefaults()
    end)
    local resetHint = label(reset, "GameFontHighlightSmall",
        "Restores every setting and all window positions and sizes. Your ratings are kept.",
        190, -52, 470, "LEFT")
    -- Centre the note vertically on the button, just to its right.
    resetHint:ClearAllPoints()
    resetHint:SetPoint("LEFT", p.resetDefaults, "RIGHT", 24, 0)
    if resetHint.SetJustifyV then resetHint:SetJustifyV("MIDDLE") end
    p.resetHint = resetHint
    resetHint:SetTextColor(unpack(MUTED))

    -- Preserve original controls/aliases for any current callers or testing.
    for _, name in ipairs({"enabled", "alertPersonal", "alertCommunity", "threshold", "thresholdValue",
        "personalThreshold", "personalThresholdValue", "highlights", "highlightGlow", "highlightBadge",
        "highlightPersonal", "highlightCommunity", "highlightChat", "minimapVisible", "partyReviewPrompt",
        "allCharacters", "confirmRemoveRating", "lookupOnHover", "debug"}) do
        scroll[name] = p[name]
    end
    self.main.settingsPanel = scroll
    scroll:Hide()
end

-- Blizzard's standard Yes/Cancel confirmation popup for Reset to Default.
function A:ConfirmResetToDefaults()
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:ResetToDefaults()
        return
    end
    StaticPopupDialogs.RATEME_RESET_DEFAULTS = StaticPopupDialogs.RATEME_RESET_DEFAULTS or {
        text = "Reset all Rate Me! settings, window positions and window sizes to their defaults?\n\nYour ratings are kept.",
        button1 = "Reset",
        button2 = CANCEL or "Cancel",
        OnAccept = function() A:ResetToDefaults() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("RATEME_RESET_DEFAULTS")
end

-- Settings > Reset to Default, then apply each restored setting immediately.
function A:ResetToDefaults()
    if not self:ResetSettingsToDefault() then return end
    for _, windowName in ipairs({"main", "editor", "reviews", "partyReview"}) do
        local frame = self[windowName]
        if frame and frame.defaultWidth then
            frame:SetSize(frame.defaultWidth, frame.defaultHeight)
        end
    end
    if self.main and self.main.pages then self.main.pages.mine = 1 end
    if self.OnAlertSettingsChanged then self:OnAlertSettingsChanged() end
    if self.OnHighlightSettingsChanged then self:OnHighlightSettingsChanged() end
    if self.OnCommunicationSettingsChanged then self:OnCommunicationSettingsChanged() end
    if self.PositionMinimapButton then self:PositionMinimapButton() end
    if self.SetMinimapVisible then self:SetMinimapVisible(self.db.settings.minimapVisible) end
    self:ArrangeWindows()
    self:DrawSettings()
    self:Log("All settings and window positions were reset to their defaults.")
end

function A:DrawSettings()
    local f = self.main
    if not f or not f.settingsPanel then return end
    local p = f.settingsPanel.content
    local settings = self.db.settings
    p.allCharacters:SetChecked(settings.allCharacters)
    p.confirmRemoveRating:SetChecked(settings.confirmRemoveRating)
    p.debug:SetChecked(settings.debug)
    p.sendRatingBroadcasts:SetChecked(settings.sendRatingBroadcasts)
    p.receiveRatingBroadcasts:SetChecked(settings.receiveRatingBroadcasts)
    p.lookupOnHover:SetChecked(settings.lookupOnHover)
    p.lookupPeerCount:SetValue(settings.lookupPeerCount or 7)
    p.lookupPeerValue:SetText(tostring(settings.lookupPeerCount or 7))
    p.enabled:SetChecked(settings.lowRatingAlerts)
    p.alertPersonal:SetChecked(settings.lowRatingPersonal)
    p.alertCommunity:SetChecked(settings.lowRatingCommunity)
    p.highlights:SetChecked(settings.ratingHighlights)
    p.highlightGlow:SetChecked(settings.ratingHighlightsGlow)
    p.highlightBadge:SetChecked(settings.ratingHighlightsBadge)
    p.highlightChat:SetChecked(settings.ratingHighlightsChat)
    p.highlightPersonal:SetChecked(settings.ratingHighlightsPersonal)
    p.highlightCommunity:SetChecked(settings.ratingHighlightsCommunity)
    p.minimapVisible:SetChecked(settings.minimapVisible)
    p.partyReviewPrompt:SetChecked(settings.partyReviewPrompt)

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
    dependent(p.highlightChat, p.highlightChatRow, p.highlightChatLabel, settings.ratingHighlights)
    local anyVisual = settings.ratingHighlights and
        (settings.ratingHighlightsGlow or settings.ratingHighlightsBadge or settings.ratingHighlightsChat)
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

-- Recent Players: players you have grouped with, with your own rating if any.
-- Players still in your group sort first, then the most recently grouped.
function A:ListRecentPlayers()
    local items = {}
    for _, entry in pairs(self.db and self.db.grouped or {}) do
        if entry.faction == self.myFaction and entry.guid ~= self.myGuid then
            local own = self:GetOwnRating(entry.guid)
            items[#items + 1] = {
                guid = entry.guid, name = entry.name, class = entry.class, faction = entry.faction,
                fromGame = entry.fromGame, inGroup = entry.inGroup, lastGrouped = entry.lastGrouped,
                score = own and not own.removed and own.score or nil,
                date = entry.inGroup and math.huge or entry.lastGrouped,
            }
        end
    end
    return items
end

function A:CreateMainRow(index)
    local f = self.main
    local b = CreateFrame("Button", nil, f.content)
    b:SetHeight(38)
    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * 40)
    b:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -(index - 1) * 40)
    local tex = b:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, index % 2 == 0 and 0.45 or 0.2)
    b.nameText = label(b, "GameFontHighlight", "",
        LIST_COLUMNS.player.x, -7, LIST_COLUMNS.player.width, "RIGHT")
    A:AttachClassIcon(b.nameText, b, function() if b:GetScript("OnClick") then b:GetScript("OnClick")(b) end end)
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
        if f.tab == "grouped" then
            A:OpenEditor(item)
        elseif f.tab == "mine" then
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
    f.tabGrouped:SetEnabled(f.tab ~= "grouped")
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
    if isSettings then f.emptyText:Hide() end
    f.dateHeading:SetText(f.tab == "recent" and "Last checked" or f.tab == "grouped" and "Last grouped"
        or "Date rated")
    f.ratingHeading:SetText(f.tab == "grouped" and "Your rating" or "Rating")
    f.clearSearch:SetEnabled((f.search:GetText() or "") ~= "")
    if isSettings then self:DrawSettings(); return end

    if f.scroller and f.scroller.GetWidth and f.content then
        local width = f.scroller:GetWidth()
        if type(width) == "number" and width > 0 then
            f.content:SetWidth(math.max(675, width - 4))
        end
    end
    local records
    if f.tab == "mine" then records = self:ListOwn()
    elseif f.tab == "grouped" then records = self:ListRecentPlayers()
    else records = self:ListRecent() end
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
    if total == 0 then
        local message
        if filter ~= "" then
            message = "No players match your search."
        elseif f.tab == "mine" then
            message = "You haven't rated anyone yet.\nRight-click a friendly player to rate them."
        elseif f.tab == "grouped" then
            message = "No players yet.\nPlayers you group with will appear here."
        else
            message = "No recent lookups yet.\nPlayers you look up will appear here."
        end
        f.emptyText:SetText(message)
        f.emptyText:Show()
    else
        f.emptyText:Hide()
    end
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
        local hasIcon = classToken(item.class) ~= nil
        -- With a class icon the name is centred alone; otherwise say what the row is.
        self:SetPlayerLabel(row.nameText, item.name, item.class, LIST_COLUMNS.player.x, hasIcon and -12 or -7)
        row.subText:SetText(hasIcon and "" or (f.tab == "mine" and "Your review" or "Community lookup"))
        if f.tab == "grouped" then
            row.scoreText:SetText(item.score and self:WindowScoreText(item.score, 14) or "Not rated")
            row.dateText:SetText(item.inGroup and "In your group" or self:DateText(item.lastGrouped))
        elseif f.tab == "mine" then
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

-- Shared tag selection for the individual editor and post-party editor.
function A:CreateTagSelection(parent, window, x, y, width, changed, sidebar)
    local c=CreateFrame("Frame",nil,parent)
    local compact=sidebar and sidebar.compact
    -- Vertical: the three chosen chips are stacked, one per row (rating editor).
    c.vertical=sidebar and sidebar.vertical
    c:SetSize(width,compact and 30 or (c.vertical and 131) or (sidebar and 60 or 410))
    c:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    c.tags,c.window,c.changed,c.tagWidth={},window,changed,width
    -- Optional: called when a chip is clicked (party rows select themselves).
    c.activate=sidebar and sidebar.activate
    -- Compact controls show only the chosen chips; the heading and count live
    -- beside the separate choices panel instead.
    c.chipY=compact and 0 or -29
    if not compact then label(c,"GameFontDisableSmall","Choose up to three tags",0,-6,width-110) end
    c.count=label(c,"GameFontDisableSmall","0 / 3 tags",width-110,-6,110,"RIGHT")
    if compact then
        c.count:Hide()
        c.empty=label(c,"GameFontDisableSmall","No tags",4,-9,width-8)
    end
    c.chips={}
    for n=1,3 do
        local slot=n
        local chip=CreateFrame("Frame",nil,c,"BackdropTemplate")
        chip:SetSize(1,30)
        chip:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,
            insets={left=3,right=3,top=3,bottom=3}})
        chip:SetBackdropColor(0.05,0.05,0.05,1)
        chip:SetBackdropBorderColor(BRONZE[1],BRONZE[2],BRONZE[3],1)
        chip.caption=label(chip,"GameFontHighlight","",8,0)
        chip.caption:ClearAllPoints()
        chip.caption:SetPoint("LEFT",chip,"LEFT",8,0)
        chip.caption:SetHeight(22)
        chip.caption:SetJustifyH("LEFT")
        if chip.caption.SetWordWrap then chip.caption:SetWordWrap(false) end
        chip.remove=CreateFrame("Button",nil,chip)
        chip.remove:SetSize(20,24)
        chip.remove:SetPoint("RIGHT",chip,"RIGHT",-4,0)
        chip.remove.caption=label(chip.remove,"GameFontNormal","X",0,0)
        chip.remove.caption:SetAllPoints(chip.remove)
        chip.remove.caption:SetJustifyH("CENTER")
        if chip.remove.caption.SetJustifyV then chip.remove.caption:SetJustifyV("MIDDLE") end
        chip.remove.caption:SetTextColor(1,0.2,0.2)
        chip.remove:SetScript("OnClick",function()
            if c.activate then c.activate() end
            table.remove(c.tags,slot)
            A:RefreshTagSelection(c)
            if c.changed then c.changed() end
        end)
        local function tooltip(owner)
            local id=c.tags[slot]
            if not id then return end
            GameTooltip:SetOwner(owner,"ANCHOR_TOP")
            GameTooltip:AddLine(A:ReviewTagText(id),1,1,1)
            GameTooltip:AddLine("Click the red X to remove this tag.",0.8,0.8,0.8)
            GameTooltip:Show()
        end
        chip:EnableMouse(true)
        chip:SetScript("OnMouseDown",function() if c.activate then c.activate() end end)
        chip:SetScript("OnEnter",tooltip)
        chip:SetScript("OnLeave",function() GameTooltip:Hide() end)
        chip.remove:SetScript("OnEnter",tooltip)
        chip.remove:SetScript("OnLeave",function() GameTooltip:Hide() end)
        c.chips[n]=chip
        chip:Hide()
    end
    c.buttons={}
    local host=sidebar and (sidebar.parent or parent) or c
    c.choices=CreateFrame("Frame",nil,host)
    c.choices:SetSize(sidebar and sidebar.width or width,408)
    c.choices:SetPoint("TOPLEFT",host,"TOPLEFT",sidebar and sidebar.x or 0,sidebar and sidebar.y or -66)
    local columnWidth=math.min(230,((sidebar and sidebar.width or width)-12)/2)
    c.columnWidth=columnWidth
    local negativeX=columnWidth+12
    label(c.choices,"GameFontNormal","Positive",0,0,columnWidth):SetTextColor(0.35,1,0.45)
    label(c.choices,"GameFontNormal","Negative",negativeX,0,columnWidth):SetTextColor(1,0.35,0.35)
    for id,tag in pairs(self.TAG_REGISTRY) do
        if not tag.retired then
            local tagId=id
            local b=button(c.choices,"",columnWidth,23,0,0,function() A:ToggleSelectionTag(c,tagId) end)
            b.caption=label(b,"GameFontHighlightSmall","",8,-5,columnWidth-28)
            if b.caption.SetWordWrap then b.caption:SetWordWrap(false) end
            -- Centre the text vertically on the button (the art's lower rim
            -- is a little deeper, so sit 1px below the true middle).
            b.caption:ClearAllPoints()
            b.caption:SetPoint("CENTER",b,"CENTER",-6,-1)
            if b.caption.SetJustifyV then b.caption:SetJustifyV("MIDDLE") end
            -- Selected tags: a check mark and a dull yellow button background.
            b.check=b:CreateTexture(nil,"OVERLAY")
            b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            b.check:SetSize(20,20)
            b.check:SetPoint("LEFT",b,"LEFT",4,0)
            b.check:Hide()
            c.buttons[id]=b
        end
    end
    self:SortTagSelection(c,{})
    return c
end

function A:SetTagSelection(control, value, counts)
    control.tags=self:ReviewTagIds(value) or {}
    self:SortTagSelection(control,counts or self:TagUsageCounts())
    self:RefreshTagSelection(control)
end

function A:RefreshTagSelection(control)
    local count=#control.tags
    control.count:SetText(tostring(count).." / 3 tags")
    -- Reserve three equal slots even when only one or two tags are selected.
    -- Fixed-size captions avoid shrinking short labels and keep every X aligned.
    local gap,padding=6,36
    local slotWidth=(control.tagWidth-2*gap)/3
    for n,chip in ipairs(control.chips) do
        local id=control.tags[n]
        if id and control.vertical then
            local width=control.tagWidth
            chip:SetWidth(width)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT",control,"TOPLEFT",0,(control.chipY or -29)-(n-1)*(30+gap))
            chip.caption:SetText(self:ReviewTagText(id))
            chip.caption:SetWidth(math.max(1,width-padding))
            chip:Show()
        elseif id then
            local left=math.floor((n-1)*(slotWidth+gap))
            local right=math.floor(n*slotWidth+(n-1)*gap)
            local width=right-left
            chip:SetWidth(width)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT",control,"TOPLEFT",left,control.chipY or -29)
            chip.caption:SetText(self:ReviewTagText(id))
            chip.caption:SetWidth(math.max(1,width-padding))
            chip:Show()
        else chip:Hide() end
    end
    if control.empty then
        if count==0 then control.empty:Show() else control.empty:Hide() end
    end
    self:DrawTagSelection(control)
end

-- Freeze the frequency order while editing so choices do not jump under the cursor.
function A:SortTagSelection(control, counts)
    local groups=self:SortedReviewTagGroups(counts)
    control.tagGroups=groups
    for _,group in ipairs({"positive","negative"}) do
        local x=group=="positive" and 0 or control.columnWidth+12
        for row,id in ipairs(groups[group]) do
            local b=control.buttons[id]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT",control.choices,"TOPLEFT",x,-(23+(row-1)*24))
        end
    end
end

-- Selected tag buttons get a dull yellow background: the button's art is
-- greyed and tinted. nil restores the normal look.
local SELECTED_BACKGROUND = {0.80, 0.68, 0.30}
-- Unselected tag buttons drop the red: the same art greyed, untinted, which
-- matches the grey of the game's disabled buttons.
local UNSELECTED_BACKGROUND = {1, 1, 1}
local function tintButton(b, color)
    local seen = {}
    local regions = {b.Left, b.Middle, b.Right,
        b.GetNormalTexture and b:GetNormalTexture(), b.GetPushedTexture and b:GetPushedTexture()}
    for i = 1, 5 do
        local texture = regions[i]
        if texture and not seen[texture] then
            seen[texture] = true
            if texture.SetDesaturated then texture:SetDesaturated(color and true or false) end
            if texture.SetVertexColor then
                if color then texture:SetVertexColor(color[1], color[2], color[3])
                else texture:SetVertexColor(1, 1, 1) end
            end
        end
    end
end

function A:DrawTagSelection(control)
    local tags=control.tags
    for id,b in pairs(control.buttons) do
        local selected=false
        local candidate={}
        for _,chosen in ipairs(tags) do
            if chosen==id then selected=true end
            candidate[#candidate+1]=chosen
        end
        candidate[#candidate+1]=id
        local available=selected or self:EncodeReviewTags(candidate)~=nil
        b:SetEnabled(available)
        -- Choices that can't be picked right now (opposite chosen, or three
        -- tags already) are shown at half opacity.
        b:SetAlpha(available and 1 or 0.5)
        b.caption:SetText(self:ReviewTagText(id))
        b.isSelected=selected
        if selected then b.check:Show() else b.check:Hide() end
        tintButton(b,selected and SELECTED_BACKGROUND or UNSELECTED_BACKGROUND)
    end
end

function A:ToggleSelectionTag(control,id)
    local candidate={}
    local found=false
    for _,chosen in ipairs(control.tags) do
        if chosen==id then found=true else candidate[#candidate+1]=chosen end
    end
    if not found then candidate[#candidate+1]=id end
    local valid=self:ReviewTagIds(candidate)
    if not valid then return end
    control.tags=valid
    self:RefreshTagSelection(control)
    if control.changed then control.changed() end
end

function A:CreateEditorWindow()
    -- Left column: player, community rating, your stars, then your chosen tags
    -- stacked below them. Right column: the tag choices. Buttons underneath.
    local f = makeFrame("RateMeEditorWindow", 960, 534, "Rate Me!")
    -- Player name as the window's heading, with the class icon and class name
    -- as a subheading underneath.
    f.targetText = label(f, "GameFontHighlightLarge", "", 28, -54, 450)
    f.classText = label(f, "GameFontHighlight", "", 28, -85, 450)
    local function resize(fs, size)
        local font, _, flags = fs.GetFont and fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    resize(f.targetText, 20)
    resize(f.classText, 14)
    self:AttachClassIcon(f.classText, f)
    label(f, "GameFontNormal", "Community rating", 28, -111)
    f.community = label(f, "GameFontHighlight", "", 28, -133, 452)
    f.freshness = label(f, "GameFontDisableSmall", "", 28, -154, 452)
    label(f, "GameFontNormal", "Your rating", 28, -183)
    f.stars = {}
    f.score = 0
    for n = 1, 5 do
        local b = button(f, "", 65, 43, 28 + (n - 1) * 75, -205, function()
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
    -- Larger number, centred vertically on the star buttons, just after them.
    f.selectedNumeric = label(f, "GameFontHighlightLarge", "", 0, 0, 120, "LEFT")
    f.selectedNumeric:ClearAllPoints()
    f.selectedNumeric:SetPoint("LEFT", f.stars[5], "RIGHT", 14, 0)
    resize(f.selectedNumeric, 24)
    f.scoreText = label(f, "GameFontHighlightSmall", "", 28, -254, 430)
    label(f, "GameFontNormal", "Your tags (optional)", 28, -284)
    f.tagControl = self:CreateTagSelection(f, f, 28, -306, 452, nil,
        {x=496, y=-70, width=432, vertical=true})
    f.save = button(f, "Save Rating", 125, 26, 28, -453, function()
        local ok, err = A:SaveOwnRating(f.target, f.score, f.tagControl.tags)
        if ok then
            f:Hide()
            A:Log("Saved your rating for " .. A:DisplayName(f.target.name))
        else
            A:Log(err or "Unable to save rating")
        end
    end)
    local function removeRating(target)
        if A:DeleteOwnRating(target) then
            A:Log("Removed your rating for " .. A:DisplayName(target.name))
            -- Only close the editor if it still shows the same player.
            if f.target == target then f:Hide() end
        end
    end
    f.remove = button(f, "Remove", 86, 26, 158, -453, function()
        local target = f.target
        if not target then return end
        if not A.db.settings.confirmRemoveRating then
            removeRating(target)
            return
        end
        A:ShowRemoveRatingConfirm(target, removeRating)
    end)
    button(f, "Cancel", 112, 26, 250, -453, function() f:Hide() end)
    self.editor = f
end

-- Confirmation for removing a rating, styled like Blizzard's own popups but
-- with a "Don't ask again" checkbox, which the stock StaticPopup lacks.
-- Ticking it and confirming turns off Settings > My Ratings > confirmation.
function A:ShowRemoveRatingConfirm(target, onAccept)
    local d = self.removeConfirm
    if not d then
        d = CreateFrame("Frame", "RateMeRemoveRatingConfirm", UIParent, "BackdropTemplate")
        d:SetWidth(400)
        d:SetFrameStrata("DIALOG")
        d:SetToplevel(true)
        d:SetClampedToScreen(true)
        d:EnableMouse(true)
        d:SetPoint("TOP", UIParent, "TOP", 0, -135)
        d:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11},
        })
        local icon = d:CreateTexture(nil, "ARTWORK")
        icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        icon:SetSize(48, 48)
        icon:SetPoint("TOPLEFT", d, "TOPLEFT", 24, -20)
        d.text = d:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        d.text:SetPoint("TOPLEFT", d, "TOPLEFT", 84, -22)
        d.text:SetWidth(292)
        d.text:SetJustifyH("LEFT")
        d.dontAsk = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
        d.dontAsk:SetSize(26, 26)
        -- Bottom row: "Don't ask again" on the left, buttons on the right.
        d.dontAsk:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 20, 16)
        local caption = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        caption:SetPoint("LEFT", d.dontAsk, "RIGHT", 2, 1)
        caption:SetText("Don't ask again")
        d.accept = button(d, "Remove", 100, 22, 0, 0, function()
            local data = d.data
            if d.dontAsk:GetChecked() then
                A:SetSetting("confirmRemoveRating", false)
                A:DrawSettings()
            end
            d.data = nil
            d:Hide()
            if data then data.onAccept(data.target) end
        end)
        d.accept:ClearAllPoints()
        d.accept:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -128, 18)
        d.cancel = button(d, CANCEL or "Cancel", 100, 22, 0, 0, function() d:Hide() end)
        d.cancel:ClearAllPoints()
        d.cancel:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -20, 18)
        d:SetScript("OnHide", function(frame) frame.data = nil end)
        if UISpecialFrames then table.insert(UISpecialFrames, "RateMeRemoveRatingConfirm") end
        d:Hide()
        self.removeConfirm = d
    end
    d.data = {target = target, onAccept = onAccept}
    d.text:SetText("Remove your rating for " .. self:DisplayName(target.name)
        .. "?")
    d.dontAsk:SetChecked(false)
    local textHeight = d.text:GetStringHeight() or 40
    d:SetHeight(math.max(110, 22 + textHeight + 20 + 22 + 18))
    d:Show()
    d:Raise()
end

function A:UpdateEditorStars()
    local f = self.editor
    if not f then return end
    for n, b in ipairs(f.stars) do
        b.starTexture:SetTexture(n <= f.score and self.STAR_FULL_TEXTURE or self.STAR_EMPTY_TEXTURE)
    end
    f.selectedNumeric:SetText(f.score > 0 and self:RatingNumberText(f.score) or "Not rated")
    f.scoreText:SetText(f.score > 0 and "Click another star to change your rating" or "Select a star to rate this player")
    f.save:SetEnabled(f.score > 0)
end
function A:UpdateEditorSummary()
    local f = self.editor
    if not f or not f.target then return end
    local summary = self:GetSummary(f.target.guid)
    f.community:SetText(self:ScoreText(summary))
    if summary and summary.checking then
        local replies = summary.replies or 0
        f.freshness:SetText(replies == 0 and "Checking reachable online reviewers..."
            or string.format("Checking reachable online reviewers... %d repl%s so far",
                replies, replies == 1 and "y" or "ies"))
    elseif summary and summary.at and summary.at > 0 then
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
    f.target = {guid = target.guid, name = target.name, faction = target.faction, class = target.class,
        fromGame = target.fromGame}
    local prior = self:GetOwnRating(f.target.guid)
    f.score = (prior and not prior.removed and prior.score) or 0
    self:SetTagSelection(f.tagControl, (prior and not prior.removed and prior.tags) or "")
    f.targetText:SetText(self:DisplayName(f.target.name))
    self:SetClassLabel(f.classText, f.target.class, 28, -85)
    f.remove:SetEnabled(prior ~= nil and not prior.removed)
    f.save:SetText(prior and not prior.removed and "Update Rating" or "Save Rating")
    self:UpdateEditorStars()
    self:UpdateEditorSummary()
    f:Show()
    self:MarkWindowShown(f)
    self:Query(f.target, false, true)
end

function A:CreateReviewsWindow()
    local REVIEWS_WIDTH, REVIEWS_HEIGHT = 650, 550
    local f = makeFrame("RateMeReviewsWindow", REVIEWS_WIDTH, REVIEWS_HEIGHT, "Rate Me! — Community Reviews")
    makeResizable(f, REVIEWS_WIDTH, 400, 1200, 1000)
    -- Player name sits beside the portrait, like the Character window's level line.
    f.targetText = label(f, "GameFontHighlight", "", 66, -34, 530)
    f.ratingText = label(f, "GameFontNormal", "", 26, -70, 572)
    f.status = label(f, "GameFontDisableSmall", "", 26, -94, 572)
    f.scroller = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroller:SetPoint("TOPLEFT", 26, -138)
    f.scroller:SetPoint("BOTTOMRIGHT", -48, 65)
    f.content = CreateFrame("Frame", nil, f.scroller)
    f.content:SetSize(562, 1)
    f.scroller:SetScrollChild(f.content)
    -- Review rows stretch with the window; never narrower than the design width.
    f.scroller:SetScript("OnSizeChanged", function(_, width)
        if type(width) == "number" and width > 0 then
            f.content:SetWidth(math.max(562, width - 14))
        end
    end)
    f.rows = {}
    f.refresh = button(f, "Refresh", 130, 26, 28, -508, function()
        if f.target then A:Query(f.target, true, true) end
    end)
    f.refresh:ClearAllPoints()
    f.refresh:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 28, REVIEWS_HEIGHT - 508)
    -- Reviews are shown 20 per page: at most 20 rows ever exist,
    -- however many reviews are saved. Pager sits bottom-right, level with Refresh.
    f.page = 1
    f.nextPage = button(f, "Next", 95, 24, 0, 0, function()
        f.page = f.page + 1
        A:DrawReviews(true)
    end)
    f.nextPage:ClearAllPoints()
    f.nextPage:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -48, REVIEWS_HEIGHT - 509)
    f.pageIndicator = label(f, "GameFontHighlightSmall", "Page 1 of 1", 0, 0, 110, "CENTER")
    f.pageIndicator:ClearAllPoints()
    f.pageIndicator:SetPoint("TOPRIGHT", f.nextPage, "TOPLEFT", -10, -6)
    f.previousPage = button(f, "Previous", 95, 24, 0, 0, function()
        f.page = math.max(1, f.page - 1)
        A:DrawReviews(true)
    end)
    f.previousPage:ClearAllPoints()
    f.previousPage:SetPoint("TOPRIGHT", f.pageIndicator, "TOPLEFT", -10, 6)
    self.reviews = f
end

function A:CreateReviewRow(index)
    local f = self.reviews
    local y = -(index - 1) * 117
    local row = CreateFrame("Frame", nil, f.content)
    row:SetHeight(111)
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -2, y)
    local tex = row:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, index % 2 == 0 and 0.45 or 0.2)
    row.nameText = label(row, "GameFontHighlight", "", 8, -8, 310)
    row.scoreText = label(row, "GameFontNormal", "", 362, -8, 180, "RIGHT")
    row.scoreText:ClearAllPoints()
    row.scoreText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -8)
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
        elseif row.vote.via then
            GameTooltip:AddLine("Peer supplied", 1, 0.75, 0.3)
            GameTooltip:AddLine("Received from "..A:DisplayName(row.vote.via).."; the original author has not been verified directly.",1,1,1,true)
            GameTooltip:AddLine("Received: "..A:DateText(row.vote.receivedAt),1,1,1,true)
        else
            GameTooltip:AddLine("Unverified author", 1, 0.75, 0.3)
            GameTooltip:AddLine("This copy has not been received directly from its author.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.verification:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.tagsText = label(row, "GameFontHighlightSmall", "", 8, -49)
    row.tagsText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -22, -49)
    row.tagsText:SetJustifyV("TOP")
    if row.tagsText.SetWordWrap then row.tagsText:SetWordWrap(false) end
    row.tagsText:SetHeight(18)
    row.block = button(row, "Hide tags", 110, 20, 432, -85, function()
        if not row.reviewer then return end
        A:ToggleReviewerBlock(row.reviewer)
        A:DrawReviews()
    end)
    row.block:ClearAllPoints()
    row.block:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -85)
    f.rows[index] = row
    return row
end

local REVIEWS_PAGE_SIZE = 20

-- pageChanged: the player moved to another page, so scroll back to the top.
function A:DrawReviews(pageChanged)
    local f = self.reviews
    if not f or not f.target then return end
    local guid = f.target.guid
    local summary = self:GetSummary(guid)
    f.targetText:SetText(self:DisplayName(f.target.name))
    f.ratingText:SetText(self:ScoreText(summary))
    if summary and summary.count > 0 then
        f.status:SetText(string.format("%d recently verified / %d cached; refresh to check for updates",
            summary.freshCount or 0, summary.cachedCount or summary.count))
    elseif summary and (summary.unverifiedCount or 0) > 0 then
        f.status:SetText("Only unverified reviews saved; refresh to reach online reviewers")
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
    -- Most useful first: your own review, then verified reviews,
    -- then unverified ones; newest first within each group.
    local ownKey = self:Key(self.myName)
    local function group(entry)
        if entry.reviewer == ownKey then return 0 end
        if self:IsCommunityReviewVerified(entry.vote) then return 1 end
        return 2
    end
    table.sort(list, function(a, b)
        local ga, gb = group(a), group(b)
        if ga ~= gb then return ga < gb end
        if a.vote.date ~= b.vote.date then return a.vote.date > b.vote.date end
        return a.reviewer < b.reviewer
    end)
    local pageCount = math.max(1, math.ceil(#list / REVIEWS_PAGE_SIZE))
    f.page = math.max(1, math.min(f.page or 1, pageCount))
    local first = (f.page - 1) * REVIEWS_PAGE_SIZE + 1
    local last = math.min(#list, f.page * REVIEWS_PAGE_SIZE)
    f.pageIndicator:SetText(string.format("Page %d of %d", f.page, pageCount))
    f.previousPage:SetEnabled(f.page > 1)
    f.nextPage:SetEnabled(f.page < pageCount)
    local shown = 0
    for position = first, last do
        local entry = list[position]
        shown = shown + 1
        local index = shown
        local row = f.rows[index] or self:CreateReviewRow(index)
        local vote = entry.vote
        row.reviewer, row.vote = entry.reviewer, vote
        local ignored = self.db.ignored[entry.reviewer]
        row.nameText:SetText(self:DisplayName(vote.sender or entry.reviewer))
        row.block:SetText(ignored and "Show tags" or "Hide tags")
        row.scoreText:SetText(self:WindowScoreText(vote.score, 15))
        row.dateText:SetText("Rated " .. self:DateText(vote.date))
        if self:IsCommunityReviewVerified(vote) then
            row.verificationText:SetText("Verified author")
            row.verificationText:SetTextColor(0.35, 1, 0.45)
        elseif entry.reviewer == self:Key(self.myName) then
            row.verificationText:SetText("Your review")
            row.verificationText:SetTextColor(1, 0.82, 0)
        elseif vote.via then
            row.verificationText:SetText("Peer supplied")
            row.verificationText:SetTextColor(1, 0.75, 0.3)
        else
            row.verificationText:SetText("Unverified author")
            row.verificationText:SetTextColor(1, 0.75, 0.3)
        end

        row.tagsText:SetText(ignored and "Tags hidden for this reviewer" or self:ReviewTagsText(vote.tags))
        row:Show()
    end
    for index = shown + 1, #f.rows do f.rows[index]:Hide() end
    f.content:SetHeight(math.max(1, shown * 117))
    if pageChanged and f.scroller.SetVerticalScroll then f.scroller:SetVerticalScroll(0) end
end

function A:OpenReviews(target)
    if not self:ValidateStoredTarget(target) then return end
    local f = self.reviews
    f.target = {guid = target.guid, name = target.name, faction = target.faction, class = target.class,
        fromGame = target.fromGame}
    f.page = 1
    self:RememberTarget(f.target)
    self:Query(f.target, false, true)
    f:Show()
    self:MarkWindowShown(f)
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
-- Player rows stay compact so a full party fits without scrolling; tag choices
-- live in a separate panel on the right, for whichever row is being edited.
local PARTY_ROW_HEIGHT = 92
local PARTY_ROW_STEP = 96
local PARTY_VISIBLE_ROWS = 4
local PARTY_ROWS_WIDTH = 662
local PARTY_TAG_PANEL_X = 732
local PARTY_TAG_PANEL_WIDTH = 432
-- Tall enough for the heading plus 16 tags per column.
local PARTY_TAG_PANEL_HEIGHT = 464
local PARTY_ROWS_TOP = -110
-- The tag panel's outer box (panel frame plus its 8px padding), in window coordinates.
local PARTY_PANEL_BOX_LEFT = 732 - 8
local PARTY_PANEL_BOX_TOP = -104 + 8
local PARTY_PANEL_BOX_BOTTOM = -104 - PARTY_TAG_PANEL_HEIGHT - 8
local PARTY_ROW_COLOR = {0.10, 0.09, 0.08}
local PARTY_ACTIVE_ROW_COLOR = {0.32, 0.27, 0.12}
local PARTY_HOVER_ROW_COLOR = {0.20, 0.18, 0.14}

function A:CreatePartyReviewWindow()
    local f = makeFrame("RateMePartyReviewWindow", 1190, 632, "Rate Me! - Rate Your Party")
    label(f, "GameFontHighlightSmall",
        "Choose stars for each player. Click a player to show their tags in the panel on the right (up to three). Leave a player unrated to skip them.",
        66, -40, 1090)
    f.status = label(f, "GameFontDisableSmall", "", 25, -79, 690)

    -- Sized for exactly four rows; scrolling is only possible (and the bar only
    -- shown) in the rare case of more players being remembered from the party.
    f.scroll = CreateFrame("ScrollFrame", "RateMePartyReviewScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -110)
    f.scroll:SetSize(PARTY_ROWS_WIDTH, PARTY_VISIBLE_ROWS * PARTY_ROW_STEP - (PARTY_ROW_STEP - PARTY_ROW_HEIGHT))
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(PARTY_ROWS_WIDTH, 1)
    f.scroll:SetScrollChild(f.content)
    f.scrollBar = f.scroll.ScrollBar or _G["RateMePartyReviewScrollScrollBar"]
    f.rows = {}

    local panel = CreateFrame("Frame", nil, f)
    panel:SetSize(PARTY_TAG_PANEL_WIDTH, PARTY_TAG_PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", PARTY_TAG_PANEL_X, -104)
    -- Same fill and gold outline as the selected row; a bridge (below) joins
    -- the two into one shape, so the panel reads as "that player's tags".
    local panelBg = panel:CreateTexture(nil, "BACKGROUND")
    panelBg:SetPoint("TOPLEFT", panel, "TOPLEFT", -8, 8)
    panelBg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 8, -8)
    panelBg:SetColorTexture(PARTY_ACTIVE_ROW_COLOR[1], PARTY_ACTIVE_ROW_COLOR[2], PARTY_ACTIVE_ROW_COLOR[3], 1)
    panel.border = {}
    -- The left edge is drawn by PositionPartyTagBridge, with an opening where
    -- the bridge from the selected row enters.
    for _, edge in ipairs({"TOP", "BOTTOM", "RIGHT"}) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        if edge == "TOP" or edge == "BOTTOM" then
            t:SetPoint(edge .. "LEFT", panelBg, edge .. "LEFT", 0, 0)
            t:SetPoint(edge .. "RIGHT", panelBg, edge .. "RIGHT", 0, 0)
            t:SetHeight(2)
        else
            t:SetPoint("TOP" .. edge, panelBg, "TOP" .. edge, 0, 0)
            t:SetPoint("BOTTOM" .. edge, panelBg, "BOTTOM" .. edge, 0, 0)
            t:SetWidth(2)
        end
        panel.border[edge] = t
    end
    for _, piece in ipairs({"leftAbove", "leftBelow"}) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        panel.border[piece] = t
    end
    panel.title = label(panel, "GameFontNormal", "Tags", 0, 0, PARTY_TAG_PANEL_WIDTH - 110)
    panel.count = label(panel, "GameFontDisableSmall", "", PARTY_TAG_PANEL_WIDTH - 110, -2, 110, "RIGHT")
    panel.hint = label(panel, "GameFontDisableSmall",
        "Choose up to three tags. Click a selected tag again to remove it.", 0, -22, PARTY_TAG_PANEL_WIDTH)
    f.tagPanel = panel

    -- Bridge across the gap from the selected row's open right side to the
    -- opening in the panel's left edge: row + bridge + panel form one outline.
    local bridge = CreateFrame("Frame", nil, f)
    bridge.fill = bridge:CreateTexture(nil, "BACKGROUND")
    bridge.fill:SetAllPoints(bridge)
    bridge.fill:SetColorTexture(PARTY_ACTIVE_ROW_COLOR[1], PARTY_ACTIVE_ROW_COLOR[2], PARTY_ACTIVE_ROW_COLOR[3], 1)
    for _, edge in ipairs({"TOP", "BOTTOM"}) do
        local line = bridge:CreateTexture(nil, "BORDER")
        line:SetPoint(edge .. "LEFT", bridge, edge .. "LEFT", 0, 0)
        line:SetPoint(edge .. "RIGHT", bridge, edge .. "RIGHT", 0, 0)
        line:SetHeight(2)
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    bridge:Hide()
    f.tagBridge = bridge
    -- Keep the bridge on its row if the list ever scrolls (more than 4 players).
    if f.scroll.HookScript then
        f.scroll:HookScript("OnVerticalScroll", function() A:PositionPartyTagBridge() end)
    end

    f.save = button(f, "Save Ratings", 155, 27, 860, -586, function()
        if f.testMode then
            f.status:SetText("|cffffd100TEST WINDOW|r - nothing is saved or shared.")
            return
        end
        local saved, failed, incomplete = 0, 0, 0
        for _, row in ipairs(f.rows) do
            if row:IsShown() and row.target and row.dirty then
                if row.score > 0 then
                    local ok, err = A:SaveOwnRating(row.target, row.score, row.tagControl.tags)
                    if ok then
                        saved = saved + 1
                        -- A partial save must not resubmit already-saved reviews.
                        row.initialScore = row.score
                        row.initialTags = A:EncodeReviewTags(row.tagControl.tags)
                        row.dirty = false
                    else
                        failed = failed + 1
                        A:Debug("Could not save a party rating: " .. tostring(err))
                    end
                elseif #row.tagControl.tags > 0 then
                    incomplete = incomplete + 1
                end
            end
        end
        if failed > 0 or incomplete > 0 then
            f.status:SetText(string.format("%d saved; %d failed; %d tag selection(s) need a star rating.",
                saved, failed, incomplete))
        else
            f:Hide()
            A:Log(string.format("Saved %d party rating%s.", saved, saved == 1 and "" or "s"))
        end
    end)
    button(f, "Not Now", 135, 27, 1029, -586, function() f:Hide() end)
    -- Loading screens close every Escape-closable window; the time lets the
    -- party popup tell that apart from the player closing it.
    f:HookScript("OnHide", function(self) self.hiddenAt = GetTime and GetTime() end)
    self.partyReview = f
end

function A:CreatePartyReviewRow(index)
    local f = self.partyReview
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(PARTY_ROWS_WIDTH - 2, PARTY_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * PARTY_ROW_STEP)
    row.index = index
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)
    row.baseAlpha = index % 2 == 0 and 1 or 0.78
    -- Gold outline (thick left edge) marks the row whose tags are in the panel.
    row.activeMark = {}
    -- No right edge: the selected row opens into the bridge to the tag panel.
    for _, edge in ipairs({"TOP", "BOTTOM", "LEFT"}) do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        if edge == "TOP" or edge == "BOTTOM" then
            t:SetPoint(edge .. "LEFT", row, edge .. "LEFT", 0, 0)
            t:SetPoint(edge .. "RIGHT", row, edge .. "RIGHT", 0, 0)
            t:SetHeight(2)
        else
            t:SetPoint("TOP" .. edge, row, "TOP" .. edge, 0, 0)
            t:SetPoint("BOTTOM" .. edge, row, "BOTTOM" .. edge, 0, 0)
            t:SetWidth(5)
        end
        t:Hide()
        row.activeMark[#row.activeMark + 1] = t
    end
    A:SetPartyRowActive(row, false)
    -- The whole row is the click target for choosing whose tags are edited.
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function() A:SelectPartyTagRow(row) end)
    row:SetScript("OnEnter", function() A:SetPartyRowHover(row, true) end)
    row:SetScript("OnLeave", function() A:SetPartyRowHover(row, false) end)
    row.nameText = label(row, "GameFontHighlight", "", 12, -8, 235)
    self:AttachClassIcon(row.nameText, row, function() A:SelectPartyTagRow(row) end)
    row.communityText = label(row, "GameFontDisableSmall", "", 12, -29, 245)
    row.stars = {}
    row.score = 0
    row.initialScore = 0
    row.initialTags = ""
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
            A:SelectPartyTagRow(row)
            row.score = n
            A:UpdatePartyReviewRow(row)
        end)
        row.stars[n] = star
    end
    row.numeric = label(row, "GameFontHighlight", "", 493, -15, 125, "RIGHT")
    row.tagControl = self:CreateTagSelection(row, f, 12, -52, PARTY_ROWS_WIDTH - 26,
        function()
            if row.loading then return end
            A:UpdatePartyReviewRow(row)
            A:RefreshPartyTagPanel()
        end,
        {parent = f.tagPanel, x = 0, y = -48, width = PARTY_TAG_PANEL_WIDTH, compact = true,
         activate = function() A:SelectPartyTagRow(row) end})
    row.tagControl.choices:Hide()
    f.rows[index] = row
    return row
end

function A:SetPartyRowActive(row, active)
    local color = active and PARTY_ACTIVE_ROW_COLOR or PARTY_ROW_COLOR
    row.background:SetColorTexture(color[1], color[2], color[3], active and 1 or row.baseAlpha)
    for _, edge in ipairs(row.activeMark) do
        if active then edge:Show() else edge:Hide() end
    end
    row.isActive = active
end

function A:SetPartyRowHover(row, hovered)
    if row.isActive then return end
    local color = hovered and PARTY_HOVER_ROW_COLOR or PARTY_ROW_COLOR
    row.background:SetColorTexture(color[1], color[2], color[3], hovered and 1 or row.baseAlpha)
end

-- Layout preview with made-up players: /rateme partytest. Saving is disabled.
function A:OpenPartyReviewTest()
    local members = {}
    for n, name in ipairs({"Testadin", "Testlock", "Testpriest", "Testrogue"}) do
        members[n] = {guid = string.format("Player-0-RateMeTest%d", n), name = name,
            class = "WARRIOR", faction = self.myFaction}
    end
    self:OpenPartyReview(members, true)
end

-- Show one row's tag choices in the side panel and mark that row as active.
function A:SelectPartyTagRow(row)
    local f = self.partyReview
    if not f then return end
    f.activeTagRow = row
    for _, other in ipairs(f.rows) do
        local active = other == row
        self:SetPartyRowActive(other, active)
        if active then other.tagControl.choices:Show() else other.tagControl.choices:Hide() end
    end
    self:PositionPartyTagBridge()
    self:RefreshPartyTagPanel()
end

-- Window-coordinate layout of the bridge and the panel's split left edge.
function A:PositionPartyTagBridge()
    local f = self.partyReview
    local row = f and f.activeTagRow
    local panel = f and f.tagPanel
    if not panel then return end
    local top, bottom
    if row and row.index then
        local offset = f.scroll.GetVerticalScroll and f.scroll:GetVerticalScroll() or 0
        local viewportBottom = PARTY_ROWS_TOP - PARTY_VISIBLE_ROWS * PARTY_ROW_STEP + (PARTY_ROW_STEP - PARTY_ROW_HEIGHT)
        local rowTop = PARTY_ROWS_TOP - (row.index - 1) * PARTY_ROW_STEP + offset
        top = math.min(rowTop, PARTY_ROWS_TOP)
        bottom = math.max(rowTop - PARTY_ROW_HEIGHT, viewportBottom)
        if bottom >= top then top, bottom = nil, nil end
    end
    local above, below = panel.border.leftAbove, panel.border.leftBelow
    above:ClearAllPoints()
    below:ClearAllPoints()
    if not top then
        f.tagBridge:Hide()
        below:Hide()
        above:SetPoint("TOPLEFT", f, "TOPLEFT", PARTY_PANEL_BOX_LEFT, PARTY_PANEL_BOX_TOP)
        above:SetSize(2, PARTY_PANEL_BOX_TOP - PARTY_PANEL_BOX_BOTTOM)
        above:Show()
        return
    end
    local rowRight = 25 + PARTY_ROWS_WIDTH - 2
    f.tagBridge:ClearAllPoints()
    f.tagBridge:SetPoint("TOPLEFT", f, "TOPLEFT", rowRight, top)
    f.tagBridge:SetSize(PARTY_PANEL_BOX_LEFT + 2 - rowRight, top - bottom)
    f.tagBridge:Show()
    above:SetPoint("TOPLEFT", f, "TOPLEFT", PARTY_PANEL_BOX_LEFT, PARTY_PANEL_BOX_TOP)
    above:SetSize(2, math.max(1, PARTY_PANEL_BOX_TOP - top + 2))
    below:SetPoint("TOPLEFT", f, "TOPLEFT", PARTY_PANEL_BOX_LEFT, bottom + 2)
    below:SetSize(2, math.max(1, bottom + 2 - PARTY_PANEL_BOX_BOTTOM))
    above:Show()
    below:Show()
end

function A:RefreshPartyTagPanel()
    local f = self.partyReview
    local row = f and f.activeTagRow
    if not row then return end
    f.tagPanel.title:SetText("Tags for " .. (row.nameText:GetText() or ""))
    f.tagPanel.count:SetText(tostring(#row.tagControl.tags) .. " / 3 tags")
end

function A:UpdatePartyReviewRow(row)
    for n, star in ipairs(row.stars) do
        star.icon:SetTexture(n <= row.score and self.STAR_FULL_TEXTURE or self.STAR_EMPTY_TEXTURE)
    end
    row.numeric:SetText(row.score > 0 and self:RatingNumberText(row.score) or "Not rated")
    row.dirty = row.score ~= row.initialScore or self:EncodeReviewTags(row.tagControl.tags) ~= row.initialTags
end

function A:OpenPartyReview(members, testMode)
    if not self.partyReview or type(members) ~= "table" or #members == 0 then return end
    local f = self.partyReview
    f.members = members
    f.testMode = testMode and true or false
    local count = 0
    local tagCounts = self:TagUsageCounts()
    for _, target in ipairs(members) do
        if self:ValidateStoredTarget(target) then
            count = count + 1
            local row = f.rows[count] or self:CreatePartyReviewRow(count)
            row.target = target
            local prior = self:GetOwnRating(target.guid)
            local hasPrior = prior and not prior.removed
            row.initialScore = hasPrior and prior.score or 0
            row.initialTags = hasPrior and prior.tags or ""
            row.score = row.initialScore
            row.loading = true
            self:SetTagSelection(row.tagControl, row.initialTags, tagCounts)
            row.loading = false
            -- Same "<class icon> Name" format as the rating window.
            self:SetPlayerLabel(row.nameText, target.name, target.class, 12, -8)
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
    f.content:SetHeight(math.max(1, count * PARTY_ROW_STEP - (PARTY_ROW_STEP - PARTY_ROW_HEIGHT)))
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
    if f.scrollBar then
        if count > PARTY_VISIBLE_ROWS then f.scrollBar:Show() else f.scrollBar:Hide() end
    end
    self:SelectPartyTagRow(f.rows[1])
    f.status:SetText(string.format("%d eligible player%s from your last party", count, count == 1 and "" or "s")
        .. (f.testMode and "  |cffffd100(TEST WINDOW - nothing is saved)|r" or ""))
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
