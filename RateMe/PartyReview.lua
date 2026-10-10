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

function A:CapturePartyMembers()
    if partyState() ~= 'party' then return end
    self.partySession = self.partySession or {}
    for i = 1, 4 do
        local target = self:CaptureUnit('party' .. i)
        if target and not self.partySession[target.guid] then
            local count = 0
            for _ in pairs(self.partySession) do count = count + 1 end
            if count < MAX_ENCOUNTERED then
                self.partySession[target.guid] = target
            end
        end
    end
end

local function copyMembers(members)
    local copied = {}
    for _, target in pairs(members or {}) do
        copied[#copied + 1] = {
            guid = target.guid, name = target.name, class = target.class, faction = target.faction,
        }
    end
    table.sort(copied, function(a, b)
        return (a.name or ''):lower() < (b.name or ''):lower()
    end)
    return copied
end

function A:OnPartyReviewRosterChange()
    if not self.partyReviewInitialized then return end
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
    self.partyReviewState = current
end

function A:TryPendingPartyReview()
    if not self.pendingPartyReview then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local members = self.pendingPartyReview
    self.pendingPartyReview = nil
    if self.db.settings.partyReviewPrompt then self:OpenPartyReview(members) end
end

function A:InitializePartyReviews()
    self.partyReviewState = partyState()
    self.partySession = {}
    self.partyReviewInitialized = true
    self:CapturePartyMembers()
    local events = CreateFrame('Frame')
    events:RegisterEvent('GROUP_ROSTER_UPDATE')
    events:RegisterEvent('PLAYER_REGEN_ENABLED')
    events:SetScript('OnEvent', function(_, event)
        if event == 'PLAYER_REGEN_ENABLED' then
            A:TryPendingPartyReview()
        else
            A:OnPartyReviewRosterChange()
        end
    end)
    self.partyReviewWatcher = events
end
