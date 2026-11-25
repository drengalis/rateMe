-- Rate Me! version 1: optional post-party rating form.
-- Retain trusted identities during the party: partyN unit tokens disappear on leave.
local _, A = ...
local MAX_ENCOUNTERED = 40

local function partyState()
    if IsInRaid and (IsInRaid() or (LE_PARTY_CATEGORY_INSTANCE and IsInRaid(LE_PARTY_CATEGORY_INSTANCE))) then
        return 'raid'
    end
    if IsInGroup and (IsInGroup() or
        (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) or
        (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))) then
        return 'party'
    end
    return 'solo'
end

-- Guild members are never offered for post-party rating.
local function isGuildmate(unit)
    if not UnitIsInMyGuild then return false end
    local ok, inGuild = pcall(UnitIsInMyGuild, unit)
    return ok and inGuild and true or false
end

function A:CapturePartyMembers()
    if partyState() ~= 'party' then return end
    self.partySession = self.partySession or {}
    for i = 1, 4 do
        local unit = 'party' .. i
        local target = self:CaptureUnit(unit)
        if target and isGuildmate(unit) then
            -- Also drops anyone captured before guild information was available.
            self.partySession[target.guid] = nil
        elseif target and not self.partySession[target.guid] then
            local count = 0
            for _ in pairs(self.partySession) do count = count + 1 end
            if count < MAX_ENCOUNTERED then
                self.partySession[target.guid] = target
            end
        end
    end
end

-- Everyone you have grouped with (party or raid, guild members included) for
-- the main window's Recent Players list. Saved across sessions in db.grouped,
-- keeping the most recent MAX_RECENT players (the Recent Lookups limit).
-- inGroup marks players in the current group; lastGrouped is when they were
-- last seen in it.
function A:CaptureSessionGroupmates()
    if not (self.db and type(self.db.grouped) == "table") then return end
    local grouped = self.db.grouped
    local units = {}
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do units[#units + 1] = 'raid' .. i end
    elseif partyState() == 'party' then
        for i = 1, 4 do units[#units + 1] = 'party' .. i end
    end
    local now = self.Stamp and self:Stamp() or (time and time()) or 0
    local present = {}
    for _, unit in ipairs(units) do
        local target = self:CaptureUnit(unit)
        if target then
            local entry = grouped[target.guid] or {guid = target.guid}
            entry.name, entry.class, entry.faction = target.name, target.class, target.faction
            entry.fromGame = target.fromGame
            entry.lastGrouped, entry.inGroup = now, true
            grouped[target.guid] = entry
            present[target.guid] = true
        end
    end
    local count = 0
    for guid, entry in pairs(grouped) do
        count = count + 1
        if entry.inGroup and not present[guid] then
            entry.inGroup = false
            entry.lastGrouped = now
        end
    end
    local limit = self.MAX_RECENT or 150
    while count > limit do
        local oldestKey, oldest
        for guid, entry in pairs(grouped) do
            local stamp = tonumber(entry.lastGrouped) or 0
            if not entry.inGroup and (oldestKey == nil or stamp < oldest) then oldestKey, oldest = guid, stamp end
        end
        if not oldestKey then break end
        grouped[oldestKey] = nil
        count = count - 1
    end
    if self.NotifyUI then self:NotifyUI() end
end

local function copyMembers(members)
    local copied = {}
    for _, target in pairs(members or {}) do
        copied[#copied + 1] = {
            guid = target.guid, name = target.name, class = target.class, faction = target.faction,
            fromGame = target.fromGame,
        }
    end
    table.sort(copied, function(a, b)
        return (a.name or ''):lower() < (b.name or ''):lower()
    end)
    return copied
end

function A:OnPartyReviewRosterChange()
    if not self.partyReviewInitialized then return end
    self:CaptureSessionGroupmates()
    local current = partyState()
    local previous = self.partyReviewState
    -- Detect party -> solo BEFORE trying to read now-invalid party unit tokens.
    if previous == 'party' and current == 'solo' then
        local members = copyMembers(self.partySession)
        self.lastPartyMembers = members
        self.partySession = nil
        if #members > 0 and self.db.settings.partyReviewPrompt then
            if InCombatLockdown and InCombatLockdown() then
                self.pendingPartyReview = members
            else
                self:OpenPartyReview(members)
            end
        end
    elseif current == 'raid' then
        -- Party converted to a raid: no party popup now or when the raid ends.
        self.partySession = nil
    elseif current == 'party' then
        if previous ~= 'party' then self.partySession = {} end
        self:CapturePartyMembers()
        -- Unit information can arrive after GROUP_ROSTER_UPDATE; retry while in a party.
        if C_Timer and C_Timer.After and not self.partyReviewRetryQueued then
            self.partyReviewRetryQueued = true
            C_Timer.After(0.4, function()
                A.partyReviewRetryQueued = false
                if A.partyReviewState == 'party' then A:CapturePartyMembers() end
            end)
        end
    end
    if current ~= 'solo' and C_Timer and C_Timer.After then
        -- Unit details can arrive late; capture the Recent Players list again.
        C_Timer.After(0.5, function() A:CaptureSessionGroupmates() end)
    end
    self.partyReviewState = current
end

function A:TryPendingPartyReview()
    if not self.pendingPartyReview then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local members = self.pendingPartyReview
    self.pendingPartyReview = nil
    if self.db.settings.partyReviewPrompt then self:OpenPartyReview(members) end
end

-- The game closes Escape-closable windows on a loading screen (hearthstone,
-- instance portals). Reopen the party popup afterwards with its choices kept.
function A:OnPartyReviewLeavingWorld()
    local f = self.partyReview
    if not f then return end
    local now = GetTime and GetTime()
    self.reopenPartyReview = f:IsShown() or (now ~= nil and f.hiddenAt == now)
end

function A:OnPartyReviewEnteringWorld()
    if not self.reopenPartyReview then return end
    self.reopenPartyReview = nil
    local function reopen()
        local f = A.partyReview
        if f and not f:IsShown() and f.members and #f.members > 0 then f:Show() end
    end
    -- Wait a moment in case the game closes windows again as the world appears.
    if C_Timer and C_Timer.After then C_Timer.After(0.2, reopen) else reopen() end
end

function A:InitializePartyReviews()
    self.partyReviewState = partyState()
    self.partySession = {}
    self.partyReviewInitialized = true
    self:CapturePartyMembers()
    self:CaptureSessionGroupmates()
    local events = CreateFrame('Frame')
    events:RegisterEvent('GROUP_ROSTER_UPDATE')
    events:RegisterEvent('PLAYER_REGEN_ENABLED')
    events:RegisterEvent('PLAYER_LEAVING_WORLD')
    events:RegisterEvent('PLAYER_ENTERING_WORLD')
    events:SetScript('OnEvent', function(_, event)
        if event == 'PLAYER_REGEN_ENABLED' then
            A:TryPendingPartyReview()
        elseif event == 'PLAYER_LEAVING_WORLD' then
            A:OnPartyReviewLeavingWorld()
        elseif event == 'PLAYER_ENTERING_WORLD' then
            A:OnPartyReviewEnteringWorld()
        else
            A:OnPartyReviewRosterChange()
        end
    end)
    self.partyReviewWatcher = events
end
