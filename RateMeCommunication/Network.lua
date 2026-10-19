local _, Communication = ...
local A = Communication.API

local PREFIX = "RATEME"
local MAX_QUEUE = 360
local MAX_HOPS = 2
local MAX_FANOUT = 3
local INITIAL_QUERY_SEEDS = 3
local EXPANSION_QUERY_SEEDS = 3
local MIN_SAMPLE_TO_STOP_EXPANDING = 5
local MAX_RATING_RESPONSES = 100 -- distinct remote reviewers accepted per lookup
local MAX_GLOBAL_INBOUND = 120   -- received RATEME packets per 10 seconds, per client
local CHUNK_DELAY = 0.35 -- <= 3 messages/sec, before server throttling

local function stableHash(value)
    local h = 0
    for i = 1, #value do h = (h * 33 + value:byte(i)) % 65521 end
    return h
end
local function jitter(maximum)
    -- Desynchronize simultaneous joins and lookup waves across clients.
    return math.random() * maximum
end

function A:BumpNetworkStat(field)
    self.netStats = self.netStats or {}
    self.netStats[field] = (self.netStats[field] or 0) + 1
end
function A:NetworkStatsText()
    local s = self.netStats or {}
    return string.format("Lookup starts: %d; expansion waves: %d; queries sent/relayed: %d/%d; "
        .. "rating replies accepted: %d; shared reviews accepted: %d; packet sends/receives: %d/%d; drops (global/peer): %d/%d; queue: %d",
        s.queriesStarted or 0, s.expansions or 0, s.querySeeds or 0, s.queryRelays or 0,
        s.repliesAccepted or 0, s.sharedReviewsAccepted or 0, s.sent or 0, s.received or 0,
        s.droppedGlobal or 0, s.droppedPeer or 0, self.outbox and #self.outbox or 0)
end

function A:QueueSend(message, channel, target, logged)
    if type(message) ~= "string" or #message > 255 or #message == 0 then return false end
    if type(channel) ~= "string" then return false end
    if channel == "WHISPER" then
        target = self:CleanName(target)
        if not target or self:Key(target) == self:Key(self.myName) then return false end
    end
    if #self.outbox >= MAX_QUEUE then
        self:BumpNetworkStat("droppedQueue")
        self:DebugPacket("DROP/queue", message, channel, target)
        return false
    end
    self.outbox[#self.outbox + 1] = {
        message = message, channel = channel, target = target, logged = logged,
        due = self:Now(), retries = 0,
    }
    return true
end

function A:FlushMessages()
    if #self.outbox == 0 or self:Now() < self.nextSend then return end
    local job = self.outbox[1]
    if self:Now() < job.due then return end
    table.remove(self.outbox, 1)
    if (job.message:sub(1,2)=="B|" or job.message:sub(1,6)=="T|1|-|")
        and self.db.settings.sendRatingBroadcasts == false then return end
    local fn = job.logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
    if type(fn) ~= "function" then
        self:Debug("Could not send an addon message: the required game messaging function is unavailable.")
        return
    end
    local ok, result = pcall(fn, PREFIX, job.message, job.channel, job.target)
    if ok and (result == nil or result == 0 or result == true) then
        self:BumpNetworkStat("sent")
        self:DebugPacket("TX", job.message, job.channel, job.target or "subscribers")
    end
    -- New clients return Enum.SendAddonMessageResult; older clients may return nil.
    local throttled = ok and (result == 3 or
        (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.AddonMessageThrottle))
    if throttled and job.retries < 3 then
        self:DebugPacket("RETRY/throttled", job.message, job.channel, job.target)
        job.retries = job.retries + 1
        job.due = self:Now() + (2 ^ job.retries)
        self.outbox[#self.outbox + 1] = job
    elseif not ok then
        self:DebugPacket("DROP/error", job.message, job.channel, job.target)
    elseif throttled then
        self:DebugPacket("DROP/throttled", job.message, job.channel, job.target)
    elseif result ~= nil and result ~= 0 and result ~= true then
        self:DebugPacket("DROP/rejected", job.message, job.channel, job.target)
    end
    self.nextSend = self:Now() + CHUNK_DELAY
end

function A:UnderInboundLimit(sender, kind, cap, seconds)
    self.inbound = self.inbound or {}
    local key = (self:Key(sender) or "unknown") .. ":" .. kind
    local now = self:Now()
    local item = self.inbound[key]
    if not item or now - item.started >= seconds then
        self.inbound[key] = {started = now, count = 1, expires = now + seconds}
        return true
    end
    if item.count >= cap then return false end
    item.count = item.count + 1
    return true
end

function A:AllowInbound(sender, kind)
    local now = self:Now()
    local global = self.globalInbound
    if not global or now - global.started >= 10 then
        global = {started = now, count = 0}
        self.globalInbound = global
    end
    if global.count >= MAX_GLOBAL_INBOUND then
        self:BumpNetworkStat("droppedGlobal")
        if not global.reported then
            self:Debug("Paused processing incoming addon messages: too many arrived in a short period. New messages will be accepted when the limit resets.")
            global.reported = true
        end
        return false
    end
    global.count = global.count + 1
    if not self:UnderInboundLimit(sender, kind=="shared" and "sharedReplies" or "all", kind=="shared" and 100 or 18, 20) then
        self:BumpNetworkStat("droppedPeer")
        global.reportedPeers = global.reportedPeers or {}
        local senderKey = self:Key(sender)
        if senderKey and not global.reportedPeers[senderKey] then
            self:Debug("Temporarily ignored more messages from " .. self:DisplayName(sender)
                .. ": this player sent too many in a short period.")
            global.reportedPeers[senderKey] = true
        end
        return false
    end
    self:BumpNetworkStat("received")
    return true
end

function A:PruneInbound()
    if not self.inbound then return end
    local now = self:Now()
    for key, item in pairs(self.inbound) do
        if not item.expires or item.expires <= now then self.inbound[key] = nil end
    end
end

-- Rotate through recently confirmed peers to avoid all clients querying the same
-- most-recently-seen three contacts. 'used' is retained across query waves.
function A:SelectQueryPeers(id, exclude, origin, maximum, used)
    local choices = self:PeerNames(nil, 120)
    local result = {}
    if #choices == 0 then return result end
    local offset = stableHash(id .. ":" .. (self.myName or "")) % #choices
    local excluded = self:Key(exclude)
    local original = self:Key(origin)
    for i = 1, #choices do
        local peer = choices[((offset + i - 1) % #choices) + 1]
        local key = self:Key(peer)
        if key and key ~= excluded and key ~= original and not (used and used[key]) then
            result[#result + 1] = peer
            if #result >= maximum then break end
        end
    end
    return result
end

function A:Discovery()
    if self:Now() - (self.lastHello or -1000) < 90 then return end
    self.lastHello = self:Now()
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        self:QueueSend(self.payload:Hello(self.protocol), "INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then
        self:QueueSend(self.payload:Hello(self.protocol), "RAID")
    elseif IsInGroup and IsInGroup() then
        self:QueueSend(self.payload:Hello(self.protocol), "PARTY")
    end
    if IsInGuild and IsInGuild() then self:QueueSend(self.payload:Hello(self.protocol), "GUILD") end
end

function A:NewRequestID()
    self.counter = (self.counter + 1) % 1000000
    return string.format("%x-%x", math.floor(self:Now() * 1000) % 0xFFFFFFF, self.counter)
end

function A:ActiveQueries()
    local count = 0
    for _, request in pairs(self.runtime.requests) do
        if request.expires > self:Now() then count = count + 1 end
    end
    return count
end

-- Each root seed causes at most 1 + 3 + 9 recipients under the two-hop,
-- three-way forwarding rule. The configurable 1-20 root peers yield up to
-- 13-260 query recipients (plus at most 100 direct vote responses).
-- Group/guild messages are discovery-only, never rating-query broadcasts.
function A:SendQueryWave(id, maximum)
    local request = self.runtime.requests[id]
    if not request or request.expires <= self:Now() then return 0 end
    local budget = self:GetLookupPeerCount()
    if request.seedCount >= budget then return 0 end
    local remaining = math.min(maximum, budget - request.seedCount)
    local selected = self:SelectQueryPeers(id .. ":" .. request.seedCount,
        nil, self.myName, remaining, request.seeded)
    local sent = 0
    for _, peer in ipairs(selected) do
        local packet = self:EncodePacket("Q", {id, request.guid, self.myName, MAX_HOPS}, peer)
        if self:QueueSend(packet, "WHISPER", peer) then
            request.seeded[self:Key(peer)] = true
            request.seedCount = request.seedCount + 1
            sent = sent + 1
            self:BumpNetworkStat("querySeeds")
            self:QueueSend(self.payload:SharedLookup(id, request.target, MAX_HOPS), "WHISPER", peer)
        end
    end
    return sent
end

function A:Query(target, force)
    if not self:ValidateStoredTarget(target) then return false end
    self:RememberTarget(target)
    local c = self.runtime.cache[target.guid]
    local t = self:Now()
    if not force and c and c.fetchedAt and t - c.fetchedAt < self.CACHE_SECONDS then return false end
    -- Coalesce lookups of the same player, even when a forced refresh is requested.
    if c and c.queryUntil and t < c.queryUntil then return false end
    if self:ActiveQueries() >= self.MAX_PENDING then return false end
    local id = self:NewRequestID()
    local pending = {id = id, guid = target.guid, target = target,
        expires = t + self.QUERY_SECONDS, votes = {}, revisions = {},
        seeded = {}, seedCount = 0, responseCount = 0}
    local own = self:GetOwnRating(target.guid)
    if own and not own.removed and own.faction == self.myFaction and own.score >= 1 and own.score <= 5 then
        pending.votes[self:Key(self.myName)] = {
            sender = self.myName, score = own.score, date = own.date,
            rev = own.rev, tags = own.tags, freshAt = t,
        }
    end
    self.runtime.requests[id] = pending
    c = c or {votes = {}}
    c.queryUntil = pending.expires
    self.runtime.cache[target.guid] = c
    self:BumpNetworkStat("queriesStarted")
    self:Debug("Started checking community ratings for " .. self:DisplayName(target.name)
        .. ". Asking reachable players with Rate Me! installed.")
    -- If peer discovery is still empty, the first delayed wave can benefit from
    -- HELLO responses arriving in the meantime.
    if #self:PeerNames(nil, 1) == 0 then self:Discovery() end
    C_Timer.After(jitter(0.6), function()
        if self.runtime.requests[id] then self:SendQueryWave(id, INITIAL_QUERY_SEEDS) end
    end)
    C_Timer.After(4 + jitter(0.6), function()
        local r = self.runtime.requests[id]
        if r and self:QueryVoteCount(r) < MIN_SAMPLE_TO_STOP_EXPANDING then
            if self:SendQueryWave(id, EXPANSION_QUERY_SEEDS) > 0 then self:BumpNetworkStat("expansions") end
        end
    end)
    C_Timer.After(9 + jitter(0.6), function()
        local r = self.runtime.requests[id]
        if r and self:QueryVoteCount(r) < MIN_SAMPLE_TO_STOP_EXPANDING then
            -- Use the remaining configured root budget in the final wave.
            if self:SendQueryWave(id, self:GetLookupPeerCount() - r.seedCount) > 0 then self:BumpNetworkStat("expansions") end
        end
    end)
    C_Timer.After(self.QUERY_SECONDS + 0.2, function()
        if self.runtime.requests[id] then self:FinishQuery(id) end
    end)
    self:NotifyUI()
    return true
end

function A:QueryVoteCount(request)
    local n = 0
    for _, vote in pairs(request.votes) do
        if vote.score and vote.score >= 1 and vote.score <= 5 then n = n + 1 end
    end
    return n
end

function A:FinishQuery(id)
    local request = self.runtime.requests[id]
    if not request then return end
    self.tagQueryHistory = self.tagQueryHistory or {}
    self.tagQueryHistory[id] = {guid=request.guid, expires=self:Now()+20}
    self.runtime.requests[id] = nil
    if self.db and self.db.settings and self.db.settings.debug then
        local count = self:QueryVoteCount(request)
        self:Debug(string.format("Finished checking ratings for %s: received %d rating%s directly from reviewers.",
            self:DisplayName(request.target.name), count, count == 1 and "" or "s"))
    end
    local target, guid = request.target, request.guid
    local cache = self.runtime.cache[guid] or {}
    cache.votes = cache.votes or {}
    for key, revision in pairs(request.revisions) do
        local prior = cache.votes[key]
        local saved = self.db.community and self.db.community[guid]
        saved = saved and saved.votes[key]
        if (not saved or revision >= saved.rev) and (not prior or not self:IsCommunityReviewVerified(prior) or revision >= prior.rev) then
            cache.votes[key] = request.votes[key]
        end
    end
    local ownKey = self:Key(self.myName)
    cache.votes[ownKey] = request.votes[ownKey]
    cache.fetchedAt = self:Now()
    cache.queryUntil = nil
    cache.lastComplete = self:Stamp()
    self.runtime.cache[guid] = cache
    local summary = self:GetSummary(guid)
    self:RememberTarget(target)
    self:SaveLookupSummary(guid, summary)
    self:NotifyUI()
    self:RefreshTooltip(guid)
    if self.RefreshHighlights then self:RefreshHighlights() end
    if self.OnRatingQueryComplete then self:OnRatingQueryComplete(guid) end
end

function A:HandleQuery(args, sender)
    local id, guid, origin, hops = self.payload:QueryFields(args, MAX_HOPS)
    if not id then return end
    -- A forwarded request may only come from a previously discovered peer.
    -- Sender identity is server-supplied; the relayed origin is not cryptographic
    -- proof, so throttle it independently and never allow unlimited relays.
    if self:Key(origin) ~= self:Key(sender) and not self.data.peers[self:Key(sender)] then return end
    local seenKey = id .. ":" .. self:Key(origin)
    if self.runtime.seen[seenKey] and self.runtime.seen[seenKey] > self:Now() then
        self:BumpNetworkStat("duplicateQueries")
        return
    end
    if not self:UnderInboundLimit(sender, "Q", 6, 20)
        or not self:UnderInboundLimit(origin, "originQ", 8, 45) then
        self:BumpNetworkStat("droppedOrigin")
        return
    end
    self.runtime.seen[seenKey] = self:Now() + 45
    if self.db and self.db.settings and self.db.settings.debug then
        self:Debug("Accepted a rating lookup from " .. self:DisplayName(sender)
            .. (hops > 0 and "; it may be passed to other peers." or "; no further forwarding requested."))
    end
    local record = self:GetOwnRating(guid)
    if record and record.faction == self.myFaction and self:Key(origin) ~= self:Key(self.myName) then
        local value = record.removed and 0 or tonumber(record.score)
        if value and value >= 0 and value <= 5 then
            self:QueueSend(self:EncodePacket("R", {id, guid, value, record.rev or 1,
                record.date or self:Stamp(), 0}, origin), "WHISPER", origin)
            self:QueueSend(self.payload:ReviewTags(id, guid, record.rev or 1, record.tags), "WHISPER", origin)
        end
    end
    if hops <= 0 then return end
    for _, peer in ipairs(self:SelectQueryPeers(id, sender, origin, MAX_FANOUT)) do
        local packet = self:EncodePacket("Q", {id, guid, origin, hops - 1}, peer)
        if self:QueueSend(packet, "WHISPER", peer) then self:BumpNetworkStat("queryRelays") end
    end
end

function A:HandleRating(args, sender)
    local id, guid, score, revision, date = self.payload:RatingFields(args)
    if not id then return end
    local request = self.runtime.requests[id]
    if not request or request.expires < self:Now() or request.guid ~= guid then return end
    local key = self:Key(sender)
    if not key or key == self:Key(self.myName) then return end
    local prior = request.revisions[key]
    if prior and prior >= revision then return end
    if not prior then
        if request.responseCount >= MAX_RATING_RESPONSES then
            self:BumpNetworkStat("droppedReplyCap")
            return
        end
        request.responseCount = request.responseCount + 1
    end
    -- Track tombstone revisions too; an old positive vote cannot revive a removal.
    local vote = {score = score, rev = revision, date = date,
        sender = self:CleanName(sender), freshAt = self:Now()}
    if not self:SaveCommunityRating(request.target, key, vote) then return end
    self:ApplyPendingReviewTags(guid, key, vote)
    request.revisions[key] = revision
    if score == 0 then
        request.votes[key] = nil
    else
        request.votes[key] = vote
    end
    -- Only a validated direct reviewer response establishes peer reachability;
    -- arbitrary unsolicited R packets must not populate the peer directory.
    self:RememberPeer(sender)
    self:BumpNetworkStat("repliesAccepted")
    if self.db and self.db.settings and self.db.settings.debug then
        if score == 0 then
            self:Debug(string.format("Accepted %s's removal of their rating for %s (update %d).",
                self:DisplayName(sender), self:DisplayName(request.target.name), revision))
        else
            self:Debug(string.format("Accepted %s's rating for %s: %d out of 5 stars (update %d).",
                self:DisplayName(sender), self:DisplayName(request.target.name), score, revision))
        end
    end
    self:NotifyUI()
end

function A:OnMessage(prefix, message, channel, sender, logged)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 255 then return end
    local canonical = self:CleanName(sender)
    if not canonical or self:Key(canonical) == self:Key(self.myName) then return end
    if type(channel) ~= "string" then return end
    if message:sub(1, 2) == "B|" and self.db.settings.receiveRatingBroadcasts == false then return end
    if not self:AllowInbound(canonical, message:sub(1,2)=="V|" and "shared" or nil) then return end
    local rawMessage = message
    local tag, decoded, args = self:DecodePacket(message, canonical)
    if not tag then
        self:DebugPacket("IGNORE/invalid-or-unsupported", rawMessage, channel, canonical)
        return
    end
    self:DebugPacket("RX", rawMessage, channel, canonical)
    message = decoded
    if logged then return end -- Written-comment transport is no longer used.
    if tag == "B" and not logged and (channel == "CHANNEL" or channel == "WHISPER"
        or channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" or channel == "GUILD") then
        self:HandleRatingBroadcast(args, canonical)
    elseif tag == "T" and (channel == "CHANNEL" or channel == "WHISPER"
        or channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" or channel == "GUILD") then
        self:HandleReviewTags(args, canonical)
    elseif tag == "H" and args and args[2] == self.protocol
        and (channel == "WHISPER" or channel == "PARTY" or channel == "RAID"
            or channel == "INSTANCE_CHAT" or channel == "GUILD") then
        local key = self:Key(canonical)
        local prior = self.data.peers[key]
        local recently = prior and prior.hello and self:Stamp() - prior.hello < 120
        -- Fresh v1 discovery may be a peer that downgraded or restarted;
        -- require it to advertise higher capabilities again before upgrading.
        self.payload:ForgetPeer(canonical)
        self:RememberPeer(canonical)
        if not recently then
            self:SetPeerHello(canonical, self:Stamp())
            -- Guild-wide discovery is receive-only for most recipients: otherwise
            -- a guild HELLO causes a large simultaneous whisper-response burst.
            local respond = channel ~= "GUILD"
                or stableHash(canonical .. ":" .. (self.myName or "")) % 32 == 0
            if respond then
                C_Timer.After(jitter(1.5), function()
                    self:QueueSend(self.payload:Ack(self.protocol), "WHISPER", canonical)
                    self:SendCapabilities(canonical)
                    if channel == "WHISPER" then
                        local names = self:PeerNames(canonical, 2)
                        if #names > 0 then
                            self:QueueSend(self.payload:Introductions(names), "WHISPER", canonical)
                        end
                    end
                end)
            end
        end
    elseif tag == "A" and channel == "WHISPER" and args and args[2] == self.protocol then
        self.payload:ForgetPeer(canonical)
        self:RememberPeer(canonical)
        self:SendCapabilities(canonical)
    elseif tag == "K" and channel == "WHISPER" then
        -- A direct, validated capability advertisement prompts one bounded
        -- reply if ours has not been sent. No upgrade is required for v1 peers.
        if self:HandleCapabilities(message, canonical) then self:SendCapabilities(canonical) end
    elseif tag == "P" and channel == "WHISPER" then
        -- Introductions aren't votes or verified identities. Probe independently.
        if not self.data.peers[self:Key(canonical)] then return end
        local introduced = self.payload:IntroductionNames(args)
        if not introduced then return end
        local count = 0
        for _, peer in ipairs(introduced) do
            if count >= 2 then break end
            if self:Key(peer) and self:Key(peer) ~= self:Key(self.myName)
                and not self.data.peers[self:Key(peer)]
                and self:UnderInboundLimit(self.myName, "introductions", 8, 900) then
                self:QueueSend(self.payload:Hello(self.protocol), "WHISPER", peer)
                count = count + 1
            end
        end
    elseif tag == "S" and channel == "WHISPER" then
        self:HandleSharedLookup(args, canonical)
    elseif tag == "V" and channel == "WHISPER" then
        self:HandleSharedReview(args, canonical)
    elseif tag == "Q" and channel == "WHISPER" then
        -- Queries never use party/raid/guild broadcasts. A received query is
        -- not by itself proof that the sender is a confirmed peer.
        self:HandleQuery(args, canonical)
    elseif tag == "R" and channel == "WHISPER" then
        self:HandleRating(args, canonical)

    end
end

function A:InitializeNetwork()
    self.outbox, self.nextSend, self.counter = {}, 0, 0
    self.netStats, self.inbound = {}, {}
    self.payload:ResetSession()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then
        self:Log("Addon messaging API not available. Local ratings still work.")
        return
    end
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
    if registered == false then self:Log("Unable to register addon message prefix.") end
    self:EnsureBroadcastChannel()
    self.netFrame = CreateFrame("Frame")
    self.netFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.netFrame:RegisterEvent("CHANNEL_UI_UPDATE")
    self.netFrame:RegisterEvent("CHAT_MSG_ADDON")
    self.netFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.netFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
    self.netFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            self:OnMessage(select(1, ...), select(2, ...), select(3, ...), select(4, ...), event == "CHAT_MSG_ADDON_LOGGED")
        elseif event == "PLAYER_ENTERING_WORLD" or event == "CHANNEL_UI_UPDATE" then
            self:EnsureBroadcastChannel()
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
            self:Discovery()
            if event == "GROUP_ROSTER_UPDATE" then self:OnGroupRosterUpdate() end
        end
    end)
    C_Timer.NewTicker(CHUNK_DELAY, function()
        self:FlushMessages()
        for id, deadline in pairs(self.runtime.seen) do
            if deadline < self:Now() then self.runtime.seen[id] = nil end
        end
    end)
    C_Timer.NewTicker(15, function() self:PruneInbound(); self:PruneReviewTags(); self:PruneSharedLookups(); self:EnsureBroadcastChannel() end)
    C_Timer.After(3 + jitter(1.5), function() self:Discovery(); self:OnGroupRosterUpdate() end)
end

