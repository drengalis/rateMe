-- Direct-author announcements only. Forwarding never establishes authorship.
local _, Communication = ...
local A = Communication.API
local CHANNEL_NAME = "RateMeNet"

function A:GetLookupPeerCount()
    local settings = self.db and self.db.settings
    return settings and settings.lookupPeerCount or 7
end

function A:EnsureBroadcastChannel()
    local settings = self.db and self.db.settings
    if not settings or (not settings.receiveRatingBroadcasts and not settings.sendRatingBroadcasts) then return end
    if GetChannelName then
        local id = GetChannelName(CHANNEL_NAME)
        if type(id) == "number" and id > 0 then return id end
    end
    if JoinTemporaryChannel and (not self.lastChannelJoin or self:Now() - self.lastChannelJoin >= 10) then
        self.lastChannelJoin = self:Now()
        pcall(JoinTemporaryChannel, CHANNEL_NAME)
    end
    if GetChannelName then
        local id = GetChannelName(CHANNEL_NAME)
        if type(id) == "number" and id > 0 then return id end
    end
end

function A:OnCommunicationSettingsChanged()
    local settings = self.db.settings
    if not settings.receiveRatingBroadcasts and not settings.sendRatingBroadcasts then
        if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL_NAME) end
    else
        self:EnsureBroadcastChannel()
    end
end

function A:ScheduleRatingBroadcast(target)
    if not self.db.settings.sendRatingBroadcasts or not self.outbox then return end
    self.pendingRatingBroadcasts = self.pendingRatingBroadcasts or {}
    local guid = target.guid
    if self.pendingRatingBroadcasts[guid] then return end
    self.pendingRatingBroadcasts[guid] = true
    -- Rapid edits coalesce into the latest record, including removal.
    C_Timer.After(3, function()
        self.pendingRatingBroadcasts[guid] = nil
        if not self.db.settings.sendRatingBroadcasts then return end
        local record = self:GetOwnRating(guid)
        if record then self:BroadcastOwnRating(record) end
    end)
end

function A:BroadcastOwnRating(record)
    if not self.db.settings.sendRatingBroadcasts then return 0 end
    local packet = self.payload:RatingBroadcast(record, record)
    if #packet > 255 then
        self:Debug("Could not announce this rating: the message exceeds the game's size limit.")
        return 0
    end
    local sent = 0
    local function queue(channel, target)
        if self:QueueSend(packet, channel, target) then sent = sent + 1 end
    end
    local id = self:EnsureBroadcastChannel()
    if id then queue("CHANNEL", id) end
    if IsInGuild and IsInGuild() then queue("GUILD") end
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then queue("INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then queue("RAID")
    elseif IsInGroup and IsInGroup() then queue("PARTY") end
    -- Also reach all recently confirmed contacts, including other backend realms.
    for _, peer in ipairs(self:PeerNames(nil, 120)) do queue("WHISPER", peer) end
    if sent == 0 then
        self:Debug("No rating announcement route is currently available. Your rating is saved locally.")
    else
        self:Debug("Queued your rating announcement on " .. sent .. " available route(s). Delivery to every user cannot be guaranteed.")
    end
    return sent
end

function A:HandleRatingBroadcast(args, sender)
    if self.db.settings.receiveRatingBroadcasts == false then return end
    local target, reviewer, vote = self.payload:BroadcastFields(args)
    if not target or self:Key(reviewer) ~= self:Key(sender) or not self:ValidateStoredTarget(target) then
        self:Debug("Ignored a rating announcement: its author or target could not be verified.")
        return
    end
    if not self:UnderInboundLimit(sender, "broadcast", 10, 30) then return end
    local key = self:Key(sender)
    local saved = self.db.community[target.guid]
    local prior = saved and saved.votes[key]
    if prior and (prior.rev > vote.rev or
        (prior.rev == vote.rev and self:IsCommunityReviewVerified(prior))) then return end
    -- An unverified copy can become verified on direct receipt of the same revision.
    vote.sender, vote.freshAt = self:CleanName(sender), self:Now()
    if not self:SaveCommunityRating(target, key, vote) then return end
    self:RememberPeer(sender)
    self:RememberTarget(target)
    local cache = self.runtime.cache[target.guid] or {votes={}}
    cache.votes[key] = vote.score > 0 and vote or nil
    cache.lastComplete = self:Stamp()
    self.runtime.cache[target.guid] = cache
    self:SaveLookupSummary(target.guid, self:GetSummary(target.guid))
    self:BumpNetworkStat("broadcastsAccepted")
    self:Debug("Saved a verified rating announcement from " .. self:DisplayName(sender)
        .. " for " .. self:DisplayName(target.name) .. ".")
    self:NotifyUI()
    self:RefreshTooltip(target.guid)
    if self.RefreshHighlights then self:RefreshHighlights() end
    if self.OnRatingQueryComplete then self:OnRatingQueryComplete(target.guid) end
end
