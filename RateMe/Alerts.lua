-- Group join alerts. All scores are derived from directly received reviewer votes.
local _, A = ...

local function getGroupTargets(self)
    local targets = {}
    local inRaid = IsInRaid and IsInRaid()
    local inGroup = IsInGroup and IsInGroup()
    if not inRaid and not inGroup then return targets end

    local n
    if inRaid then
        n = GetNumGroupMembers and GetNumGroupMembers() or 0
    else
        -- Unlike GetNumGroupMembers, this excludes the player in a party.
        n = GetNumSubgroupMembers and GetNumSubgroupMembers() or
            math.max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1)
    end
    for i = 1, math.min(n, inRaid and 40 or 4) do
        local unit = (inRaid and "raid" or "party") .. i
        local target = self:CaptureUnit(unit) -- verifies player, faction, friendliness, GUID
        if target then targets[#targets + 1] = target end
    end
    return targets
end

function A:WantsCommunityAlerts()
    local settings = self.db and self.db.settings
    return settings and settings.lowRatingAlerts and settings.lowRatingCommunity
end

function A:WarnForLowRating(target)
    if not self.db or not self.db.settings.lowRatingAlerts then return false end
    if not target or not self.groupMembers or not self.groupMembers[target.guid] then return false end
    if self.groupWarned[target.guid] then return false end

    local settings = self.db.settings
    local triggered = {}
    if settings.lowRatingPersonal then
        local own = self:GetPersonalScore(target.guid)
        if own and own <= settings.lowRatingPersonalThreshold then
            triggered[#triggered + 1] = string.format("Your rating: %s (threshold %.1f)",
                self:StarMarkup(own, 13), settings.lowRatingPersonalThreshold)
        end
    end
    if settings.lowRatingCommunity then
        local community, count = self:GetFreshCommunityScore(target.guid)
        if community and community <= settings.lowRatingThreshold then
            triggered[#triggered + 1] = string.format("Community: %s (%d rating%s; threshold %.1f)",
                self:StarMarkup(community, 13), count, count == 1 and "" or "s", settings.lowRatingThreshold)
        end
    end
    if #triggered == 0 then return false end

    -- At most one combined warning per player per group membership.
    self.groupWarned[target.guid] = true
    local name = self:DisplayName(target.name)
    local message = name .. " joined your group — " .. table.concat(triggered, "; ")
    self:Log("|cffff6666Low rating warning:|r " .. message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("Rate Me! Low rating: " .. name, 1, 0.35, 0.25, 1)
    end
    return true
end

function A:ScanGroup()
    if not self.ready or not self.groupMembers then return end
    local previous = self.groupMembers
    local current = {}
    for _, target in ipairs(getGroupTargets(self)) do
        current[target.guid] = target
        if not previous[target.guid] then
            self.groupPending[target.guid] = target
        end
    end
    for guid in pairs(previous) do
        if not current[guid] then
            self.groupPending[guid] = nil
            self.groupWarned[guid] = nil
        end
    end
    self.groupMembers = current
    for _, target in pairs(current) do self:WarnForLowRating(target) end
    if self:WantsCommunityAlerts() then self:ProcessGroupLookups() end
end

function A:ProcessGroupLookups()
    if not self:WantsCommunityAlerts() then return end
    if not self.groupPending or not self.groupMembers then return end
    if self:ActiveQueries() >= self.MAX_PENDING then return end

    -- Start at most one new lookup at a time, to avoid raid roster network bursts.
    for guid, target in pairs(self.groupPending) do
        if not self.groupMembers[guid] then
            self.groupPending[guid] = nil
        else
            local summary = self:GetSummary(guid)
            if summary and summary.fresh then
                self.groupPending[guid] = nil
                self:WarnForLowRating(target)
            elseif self:Query(target) then
                self.groupPending[guid] = nil
                return
            end
        end
    end
end

function A:OnRatingQueryComplete(guid)
    local target = self.groupMembers and self.groupMembers[guid]
    if target then self:WarnForLowRating(target) end
    -- A completed request frees up a slot for additional party / raid members.
    if self:WantsCommunityAlerts() then self:ProcessGroupLookups() end
end

function A:OnGroupRosterUpdate()
    -- A small debounce allows a newly joined unit to become available.
    if self.groupScanQueued then return end
    self.groupScanQueued = true
    C_Timer.After(0.5, function()
        self.groupScanQueued = false
        self:ScanGroup()
    end)
end

function A:OnAlertSettingsChanged()
    if not self.groupMembers then return end
    -- Do not repeat alerts for the same member simply because settings change.
    -- A newly enabled alert may immediately report existing low-rated members.
    if self.db.settings.lowRatingAlerts then
        for guid, target in pairs(self.groupMembers) do
            if self:WantsCommunityAlerts() then
                local community = self:GetFreshCommunityScore(guid)
                if not community then self.groupPending[guid] = target end
            else
                self.groupPending[guid] = nil
            end
        end
        self:ScanGroup()
    else
        self.groupPending = {}
    end
end

function A:InitializeAlerts()
    self.groupMembers = {}
    self.groupPending = {}
    self.groupWarned = {}
    self.groupScanQueued = false
    -- Process queued party/raid lookups gradually; rescan periodically to recover
    -- when a unit token wasn't yet resolvable on the initial roster event.
    C_Timer.NewTicker(1.5, function() self:ProcessGroupLookups() end)
    C_Timer.NewTicker(12, function() self:ScanGroup() end)
end
