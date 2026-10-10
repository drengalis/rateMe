-- Rating-based visual highlights for friendly players.
-- In the open world: glow around customizable, visible friendly nameplates.
-- In parties/raids: glow around supported Blizzard unit frames.
-- Never attempt to modify forbidden nameplates or protected frames in combat.
local _, A = ...

local GOLD = {1.00, 0.72, 0.18}
local RED  = {1.00, 0.19, 0.22}
local SCAN_INTERVAL = 2
local PASSIVE_QUERY_INTERVAL = 10
local PASSIVE_QUERIES_PER_MINUTE = 6
local PENDING_LIMIT = 20

function A:HighlightColor(guid)
    if not self.db or not self.db.settings.ratingHighlights then return nil end
    local settings = self.db.settings
    local personal = settings.ratingHighlightsPersonal and self:GetPersonalScore(guid) or nil
    local community = settings.ratingHighlightsCommunity and self:GetFreshCommunityScore(guid) or nil
    -- With both sources enabled, red takes precedence over gold. A neutral
    -- personal score must not conceal a low community score, or vice versa.
    if (personal and personal < 2) or (community and community < 2) then return RED end
    if (personal and personal >= 4) or (community and community >= 4) then return GOLD end
    return nil
end

local function usable(frame)
    if not frame then return false end
    local ok, allowed = pcall(function()
        return not frame.IsForbidden or not frame:IsForbidden()
    end)
    return ok and allowed
end

local function isPvEInstance()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    return ok and inside and (kind == "party" or kind == "raid")
end

-- An actual diffuse glow, not a rectangular coloured border. The three
-- bundled white textures contain smooth alpha gradients and are tinted here.
-- Each is 32-bit TGA so no external addon or font glyph is required.
local GLOW_MEDIA = "Interface\\AddOns\\RateMe\\Media\\"
local GLOW_SPREAD = 36

local function glowTexture(overlay, path)
    local texture = overlay:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(GLOW_MEDIA .. path)
    texture:SetBlendMode("ADD")
    return texture
end

local function makeGlow(anchor, nameplate)
    -- The overlay is deliberately not parented to a protected Blizzard frame.
    -- Its points track the visible health bar (where available) without
    -- changing the nameplate's dimensions or its native health-bar colours.
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:EnableMouse(false)
    overlay:SetAllPoints(anchor)
    if nameplate then
        overlay:SetFrameStrata("HIGH")
    else
        local ok, strata = pcall(function() return anchor:GetFrameStrata() end)
        overlay:SetFrameStrata(ok and strata or "MEDIUM")
    end
    local ok, level = pcall(function() return anchor:GetFrameLevel() end)
    overlay:SetFrameLevel((ok and type(level) == "number" and level or 1) + 4)
    overlay.glowTextures = {}
    local function add(path, point, relativePoint, width, height, secondary, secondaryPoint)
        local tex = glowTexture(overlay, path)
        if width then tex:SetWidth(width) end
        if height then tex:SetHeight(height) end
        tex:SetPoint(point, overlay, relativePoint, 0, 0)
        if secondary then tex:SetPoint(secondary, overlay, secondaryPoint, 0, 0) end
        overlay.glowTextures[#overlay.glowTextures + 1] = tex
    end
    -- Two horizontal gradients and two vertical gradients. No solid
    -- SetColorTexture borders: all four sides fade smoothly into the world.
    add("GlowHorizontal.tga", "LEFT", "TOPLEFT", nil, GLOW_SPREAD, "RIGHT", "TOPRIGHT")
    add("GlowHorizontal.tga", "LEFT", "BOTTOMLEFT", nil, GLOW_SPREAD, "RIGHT", "BOTTOMRIGHT")
    add("GlowVertical.tga", "TOP", "TOPLEFT", GLOW_SPREAD, nil, "BOTTOM", "BOTTOMLEFT")
    add("GlowVertical.tga", "TOP", "TOPRIGHT", GLOW_SPREAD, nil, "BOTTOM", "BOTTOMRIGHT")
    -- Soft radial corners smooth the transition between the four edges.
    for _, point in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
        local tex = glowTexture(overlay, "GlowCorner.tga")
        tex:SetSize(GLOW_SPREAD, GLOW_SPREAD)
        tex:SetPoint("CENTER", overlay, point, 0, 0)
        overlay.glowTextures[#overlay.glowTextures + 1] = tex
    end
    function overlay:SetRatingColor(color)
        for _, texture in ipairs(self.glowTextures) do
            texture:SetVertexColor(color[1], color[2], color[3], 0.85)
        end
        self:Show()
    end
    overlay:Hide()
    return overlay
end

-- Limit the aura to the actual nameplate health bar when WoW exposes it.
-- The previous effect outlined the whole UnitFrame and looked like a box.
local function visibleBar(frame)
    if not usable(frame) then return false end
    local ok, visible = pcall(function()
        if frame.IsVisible and not frame:IsVisible() then return false end
        if frame.GetWidth and frame:GetWidth() <= 5 then return false end
        if frame.GetHeight and frame:GetHeight() <= 2 then return false end
        return true
    end)
    return ok and visible
end

local function nameplateGlowAnchor(plate)
    local unitFrame = plate and plate.UnitFrame
    if not usable(unitFrame) then return plate end
    -- Check these separately; a Lua sequence cannot contain nil slots when
    -- iterating with ipairs (the first missing property would stop the scan).
    if visibleBar(unitFrame.healthBar) then return unitFrame.healthBar end
    if visibleBar(unitFrame.HealthBar) then return unitFrame.HealthBar end
    local bars = unitFrame.HealthBarsContainer
    if usable(bars) then
        if visibleBar(bars.healthBar) then return bars.healthBar end
        if visibleBar(bars.HealthBar) then return bars.HealthBar end
    end
    return unitFrame
end

function A:QueuePassiveHighlightLookup(target)
    if not self.db.settings.ratingHighlights or not self.db.settings.ratingHighlightsCommunity
        or not self:ValidateStoredTarget(target) then return end
    local current = self:GetSummary(target.guid)
    if current and current.fresh then return end
    if self.pendingHighlightTargets[target.guid] then return end
    local queued = 0
    for _ in pairs(self.pendingHighlightTargets) do queued = queued + 1 end
    if queued >= PENDING_LIMIT then return end
    self.pendingHighlightTargets[target.guid] = {target = target, added = self:Now()}
end

function A:ProcessPassiveHighlightLookups()
    if not self.db.settings.ratingHighlights or not self.db.settings.ratingHighlightsCommunity
        or isPvEInstance() then return end
    local now = self:Now()
    local budget = self.passiveHighlightBudget
    if now - budget.started >= 60 then
        budget.started, budget.count = now, 0
    end
    if budget.count >= PASSIVE_QUERIES_PER_MINUTE then return end
    if now - self.lastHighlightQuery < PASSIVE_QUERY_INTERVAL then return end
    for guid, pending in pairs(self.pendingHighlightTargets) do
        local current = self:GetSummary(guid)
        if current and current.fresh or now - pending.added > 35 then
            self.pendingHighlightTargets[guid] = nil
        elseif self:ActiveQueries() < self.MAX_PENDING and self:Query(pending.target) then
            self.pendingHighlightTargets[guid] = nil
            budget.count = budget.count + 1
            self.lastHighlightQuery = now
            return
        end
    end
end

function A:OnNameplateAdded(unit)
    if not self.db.settings.ratingHighlights or isPvEInstance() then return end
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not usable(plate) then return end
    local target = self:CaptureUnit(unit)
    if not target then return end
    local entry = self.nameplateHighlights[plate]
    if not entry then
        if InCombatLockdown and InCombatLockdown() then return end
        -- Prefer the visible health bar instead of outlining the entire
        -- nameplate (which produces an oversized rectangular selection box).
        local anchor = nameplateGlowAnchor(plate)
        if not usable(anchor) then return end
        local okGlow, overlay = pcall(makeGlow, anchor, true)
        if not okGlow or not overlay then
            self:Debug("Unable to create nameplate glow: " .. tostring(overlay))
            return
        end
        entry = {overlay = overlay, anchor = anchor}
        self.nameplateHighlights[plate] = entry
    elseif not (InCombatLockdown and InCombatLockdown()) then
        local anchor = nameplateGlowAnchor(plate)
        if usable(anchor) and anchor ~= entry.anchor then
            local okAnchor = pcall(function()
                entry.overlay:ClearAllPoints()
                entry.overlay:SetAllPoints(anchor)
            end)
            if okAnchor then entry.anchor = anchor end
        end
    end
    entry.unit, entry.guid = unit, target.guid
    local color = self:HighlightColor(target.guid)
    if color then entry.overlay:SetRatingColor(color) else entry.overlay:Hide() end
    local summary = self:GetSummary(target.guid)
    if self.db.settings.ratingHighlightsCommunity and (not summary or not summary.fresh) then
        self:QueuePassiveHighlightLookup(target)
    end
end

function A:OnNameplateRemoved(unit)
    for _, entry in pairs(self.nameplateHighlights) do
        if entry.unit == unit then
            entry.unit, entry.guid = nil, nil
            entry.overlay:Hide()
        end
    end
end

local function frameUnit(frame)
    if not usable(frame) then return nil end
    local ok, unit = pcall(function()
        if frame.GetUnit then
            local value = frame:GetUnit()
            if type(value) == "string" then return value end
        end
        if type(frame.unit) == "string" then return frame.unit end
        if type(frame.unitToken) == "string" then return frame.unitToken end
        if frame.GetAttribute then return frame:GetAttribute("unit") end
        return nil
    end)
    if ok and type(unit) == "string" then return unit end
    return nil
end

local function collectBlizzardGroupFrames()
    local frames = {}
    local function insert(frame)
        if usable(frame) and frame.IsShown and frame:IsShown() then
            frames[frame] = true
        end
    end
    -- Retail-derived party layout (also found in newer Classic/Forever clients).
    local party = _G.PartyFrame
    if usable(party) and party.PartyMemberFramePool and party.PartyMemberFramePool.EnumerateActive then
        pcall(function()
            for frame in party.PartyMemberFramePool:EnumerateActive() do insert(frame) end
        end)
    end
    for i = 1, 5 do
        insert(_G["CompactPartyFrameMember" .. i])
        insert(_G["PartyMemberFrame" .. i])
    end
    -- Blizzard's compact raid and raid-style party frames, if present.
    for i = 1, 40 do insert(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for m = 1, 5 do insert(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
    end
    return frames
end

function A:RefreshHighlights()
    if not self.nameplateHighlights then return end
    local enabled = self.db.settings.ratingHighlights
    -- Do not touch secure frame geometry/anchors during combat. Existing glows
    -- can change colors; new party/raid overlays are installed out of combat.
    for plate, entry in pairs(self.nameplateHighlights) do
        if not enabled or isPvEInstance() or not usable(plate) or not entry.unit then
            entry.overlay:Hide()
        else
            local current = self:CaptureUnit(entry.unit)
            if not current or current.guid ~= entry.guid then
                entry.overlay:Hide()
                entry.guid, entry.unit = nil, nil
            else
                -- Blizzard sometimes lays out the health bar after the unit-
                -- added event. Move the unprotected overlay onto it when ready.
                if not (InCombatLockdown and InCombatLockdown()) then
                    local anchor = nameplateGlowAnchor(plate)
                    if usable(anchor) and anchor ~= entry.anchor then
                        local okAnchor = pcall(function()
                            entry.overlay:ClearAllPoints()
                            entry.overlay:SetAllPoints(anchor)
                        end)
                        if okAnchor then entry.anchor = anchor end
                    end
                end
                local color = self:HighlightColor(entry.guid)
                if color then entry.overlay:SetRatingColor(color) else entry.overlay:Hide() end
            end
        end
    end
    if not enabled then
        for _, entry in pairs(self.groupFrameHighlights) do entry.overlay:Hide() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    local frames = collectBlizzardGroupFrames()
    for frame in pairs(frames) do
        local unit = frameUnit(frame)
        local target = unit and self:CaptureUnit(unit)
        local entry = self.groupFrameHighlights[frame]
        if target then
            if not entry then
                entry = {overlay = makeGlow(frame, false)}
                self.groupFrameHighlights[frame] = entry
            end
            local color = self:HighlightColor(target.guid)
            if color then entry.overlay:SetRatingColor(color) else entry.overlay:Hide() end
        elseif entry then
            entry.overlay:Hide()
        end
    end
    for frame, entry in pairs(self.groupFrameHighlights) do
        if not frames[frame] then entry.overlay:Hide() end
    end
end

function A:OnHighlightSettingsChanged()
    if not self.db.settings.ratingHighlights or not self.db.settings.ratingHighlightsCommunity then
        self.pendingHighlightTargets = {}
    end
    self:RefreshHighlights()
    if self.db.settings.ratingHighlights and C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                if plate then
                    local unit = plate.namePlateUnitToken or plate.unit or
                        (plate.UnitFrame and plate.UnitFrame.unit)
                    if type(unit) == "string" then self:OnNameplateAdded(unit) end
                end
            end
        end
    end
end

function A:InitializeHighlights()
    self.nameplateHighlights = {}
    self.groupFrameHighlights = {}
    self.pendingHighlightTargets = {}
    self.passiveHighlightBudget = {started = self:Now(), count = 0}
    self.lastHighlightQuery = self:Now() - PASSIVE_QUERY_INTERVAL
    local events = CreateFrame("Frame")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            A:OnNameplateAdded(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            A:OnNameplateRemoved(unit)
        elseif event == "PLAYER_REGEN_ENABLED" then
            A:OnHighlightSettingsChanged()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Hide all old plate overlays across instance/zone transitions.
            for _, entry in pairs(A.nameplateHighlights) do entry.overlay:Hide(); entry.guid = nil; entry.unit = nil end
            A:RefreshHighlights()
        else
            A:RefreshHighlights()
        end
    end)
    self.highlightEvents = events
    C_Timer.NewTicker(SCAN_INTERVAL, function() A:RefreshHighlights() end)
    C_Timer.NewTicker(PASSIVE_QUERY_INTERVAL, function() A:ProcessPassiveHighlightLookups() end)
    C_Timer.After(1, function() A:OnHighlightSettingsChanged() end)
end
