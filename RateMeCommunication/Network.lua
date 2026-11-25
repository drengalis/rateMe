local _, Communication = ...
local A = Communication.API

local PREFIX = "RATEME"
local MAX_QUEUE = 360
-- Rating announcements (B and broadcast T packets) are "bulk": they always wait
-- behind lookups, replies and discovery, and may only fill part of the queue,
-- so announcing a rating can never delay or crowd out lookups.
local MAX_BULK_QUEUE = 120
local function isBulk(message)
    return message:sub(1, 2) == "B|" or message:sub(1, 6) == "T|1|-|"
end
local MAX_HOPS = 2
local MAX_FANOUT = 3
local INITIAL_QUERY_SEEDS = 3
local EXPANSION_QUERY_SEEDS = 3
local MIN_SAMPLE_TO_STOP_EXPANDING = 5
local MAX_RATING_RESPONSES = 100 -- distinct remote reviewers accepted per lookup
local MAX_GLOBAL_INBOUND = 120   -- received RATEME packets per 10 seconds, per client
local CHUNK_DELAY = 0.35 -- <= 3 messages/sec, before server throttling
-- Outgoing lookup budget. Each lookup makes other players' clients reply and
-- forward on our behalf, so automatic lookups (tooltips, nameplates, group
-- alerts) are spaced out and capped. Lookups the player starts
-- (opening a rating or reviews window, Refresh) always go, but still count.
local LOOKUP_MIN_INTERVAL = 2    -- seconds between automatic lookups
local LOOKUP_PER_MINUTE = 15     -- all lookups, per rolling 60-second window
-- Automatic lookups that cannot start yet wait in one shared queue and start
-- as soon as the budget allows. Priority 1: tooltips and group alerts.
-- Priority 2: nameplates, which also keep their own lower cap.
local LOOKUP_QUEUE_MAX = 30
local LOOKUP_QUEUE_TTL = {60, 35}           -- seconds an entry may wait, by priority
local BACKGROUND_LOOKUPS_PER_MINUTE = 6     -- priority-2 starts per minute

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

-- urgent: messages for a lookup the player started (rating or reviews window,
-- Refresh) go ahead of everything else waiting, after earlier urgent ones.
function A:QueueSend(message, channel, target, logged, urgent)
    if type(message) ~= "string" or #message > 255 or #message == 0 then return false end
    if type(channel) ~= "string" then return false end
    if channel == "WHISPER" then
        target = self:CleanName(target)
        if not target or self:Key(target) == self:Key(self.myName) then return false end
    end
    local bulk = isBulk(message)
    local bulkCount = 0
    for _, job in ipairs(self.outbox) do if job.bulk then bulkCount = bulkCount + 1 end end
    if bulk and bulkCount >= MAX_BULK_QUEUE then
        self:BumpNetworkStat("droppedQueue")
        self:DebugPacket("DROP/queue", message, channel, target)
        return false
    end
    if #self.outbox >= MAX_QUEUE then
        -- A full queue makes room for lookups and replies by dropping the
        -- newest announcement; announcements never displace anything.
        local victim
        if not bulk then
            for index = #self.outbox, 1, -1 do
                if self.outbox[index].bulk then victim = index; break end
            end
        end
        if not victim then
            self:BumpNetworkStat("droppedQueue")
            self:DebugPacket("DROP/queue", message, channel, target)
            return false
        end
        local dropped = table.remove(self.outbox, victim)
        self:BumpNetworkStat("droppedQueue")
        self:DebugPacket("DROP/queue", dropped.message, dropped.channel, dropped.target)
    end
    local job = {
        message = message, channel = channel, target = target, logged = logged,
        due = self:Now(), retries = 0, bulk = bulk, urgent = urgent and not bulk or nil,
    }
    local at = #self.outbox + 1
    if job.urgent then
        at = #self.outbox + 1
        for index, queued in ipairs(self.outbox) do
            if not queued.urgent then at = index; break end
        end
    elseif not bulk then
        -- Lookups, replies and discovery go ahead of every waiting announcement.
        for index, queued in ipairs(self.outbox) do
            if queued.bulk then at = index; break end
        end
    end
    table.insert(self.outbox, at, job)
    return true
end

function A:FlushMessages()
    if #self.outbox == 0 or self:Now() < self.nextSend then return end
    -- Send the first message that is due. A message waiting to be retried
    -- (WoW held it back) must not hold up everything queued behind it.
    local index
    for i, queued in ipairs(self.outbox) do
        if self:Now() >= queued.due then index = i; break end
    end
    if not index then return end
    local job = table.remove(self.outbox, index)
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
    -- Per-sender limit first: messages from a player who is over their own
    -- limit are dropped WITHOUT using the shared allowance, so one flooding
    -- client cannot crowd out everyone else's lookups and ratings.
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
    if global.count >= MAX_GLOBAL_INBOUND then
        self:BumpNetworkStat("droppedGlobal")
        if not global.reported then
            self:Debug("Paused processing incoming addon messages: too many arrived in a short period. New messages will be accepted when the limit resets.")
            global.reported = true
        end
        return false
    end
    global.count = global.count + 1
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

-- Choose peers for a lookup wave or a forwarded request: friends
-- and guildmates first, then proven peers, with about a quarter of the spots
-- kept for newcomers so the network can still grow. Within each tier the
-- starting point rotates per request, so lookups spread across peers.
-- 'used' (keys already asked) is retained across query waves.
function A:SelectQueryPeers(id, exclude, origin, maximum, used)
    local result = {}
    if not maximum or maximum <= 0 then return result end
    local excluded, original = self:Key(exclude), self:Key(origin)
    local tiers = {{}, {}, {}}
    for _, peer in ipairs(self:RankedPeers(nil)) do
        if peer.key ~= excluded and peer.key ~= original and not (used and used[peer.key]) then
            local list = tiers[peer.tier]
            list[#list + 1] = peer.name
        end
    end
    local offset = stableHash(id .. ":" .. (self.myName or ""))
    local function rotated(list)
        local out = {}
        for i = 1, #list do out[i] = list[((offset + i - 1) % #list) + 1] end
        return out
    end
    local established = rotated(tiers[1])
    for _, name in ipairs(rotated(tiers[2])) do established[#established + 1] = name end
    local newcomers = rotated(tiers[3])
    local newcomerSlots = math.min(#newcomers, math.max(1, math.floor(maximum / 4)))
    local establishedSlots = math.min(#established, maximum - newcomerSlots)
    -- Fill any spots one group cannot use from the other.
    newcomerSlots = math.min(#newcomers, maximum - establishedSlots)
    for i = 1, establishedSlots do result[#result + 1] = established[i] end
    for i = 1, newcomerSlots do result[#result + 1] = newcomers[i] end
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
        if self:QueueSend(packet, "WHISPER", peer, nil, request.interactive) then
            request.seeded[self:Key(peer)] = true
            request.seedCount = request.seedCount + 1
            sent = sent + 1
            self:BumpNetworkStat("querySeeds")
            self:QueueSend(self.payload:SharedLookup(id, request.target, MAX_HOPS), "WHISPER", peer, nil,
                request.interactive)
        end
    end
    return sent
end

-- Start a lookup now if possible, otherwise queue it. Returns true when the
-- lookup started, is queued, is already running or is not needed (fresh).
function A:RequestLookup(target, priority)
    priority = priority == 2 and 2 or 1
    local started, reason = self:Query(target)
    if started or reason == "fresh" or reason == "running" then return true end
    if reason ~= "busy" and reason ~= "budget" then return false end
    local queue = self.lookupQueue or {}
    self.lookupQueue = queue
    for _, entry in ipairs(queue) do
        if entry.target.guid == target.guid then
            if priority < entry.priority then entry.priority = priority end
            return true
        end
    end
    if #queue >= LOOKUP_QUEUE_MAX then
        -- Full: make room by dropping the oldest lowest-priority entry, but
        -- never drop a priority-1 entry for a priority-2 one.
        local drop
        for index = #queue, 1, -1 do
            if queue[index].priority >= priority and (not drop or queue[index].priority >= queue[drop].priority) then
                drop = index
            end
        end
        if not drop then return false end
        for index = 1, #queue do
            if queue[index].priority == queue[drop].priority then drop = index; break end
        end
        table.remove(queue, drop)
    end
    queue[#queue + 1] = {target = target, priority = priority, added = self:Now()}
    self:BumpNetworkStat("queuedLookups")
    return true
end

function A:ProcessLookupQueue()
    local queue = self.lookupQueue
    if not queue or #queue == 0 then return end
    local now = self:Now()
    for index = #queue, 1, -1 do
        local entry = queue[index]
        if now - entry.added > LOOKUP_QUEUE_TTL[entry.priority] then table.remove(queue, index) end
    end
    local background = self.backgroundLookupBudget
    if not background or now - background.started >= 60 then
        background = {started = now, count = 0}
        self.backgroundLookupBudget = background
    end
    -- Oldest priority-1 entry first, then the oldest priority-2 entry.
    for _, wanted in ipairs({1, 2}) do
        for index, entry in ipairs(queue) do
            if entry.priority == wanted then
                if wanted == 2 and background.count >= BACKGROUND_LOOKUPS_PER_MINUTE then break end
                local started, reason = self:Query(entry.target)
                if started then
                    table.remove(queue, index)
                    if wanted == 2 then background.count = background.count + 1 end
                    return
                elseif reason == "busy" or reason == "budget" then
                    return -- try again on the next tick
                else
                    table.remove(queue, index) -- fresh, running or no longer valid
                    return
                end
            end
        end
    end
end

function A:Query(target, force, interactive)
    if not self:ValidateStoredTarget(target) then return false, "invalid" end
    self:RememberTarget(target)
    local c = self.runtime.cache[target.guid]
    local t = self:Now()
    if not force and c and c.fetchedAt and t - c.fetchedAt < self.CACHE_SECONDS then return false, "fresh" end
    -- Coalesce lookups of the same player, even when a forced refresh is requested.
    if c and c.queryUntil and t < c.queryUntil then return false, "running" end
    -- Lookups the player starts always run, even past the limit on automatic
    -- lookups running at once; otherwise the window would wait on nothing.
    if not interactive and self:ActiveQueries() >= self.MAX_PENDING then return false, "busy" end
    local budget = self.lookupBudget
    if not budget or t - budget.started >= 60 then
        budget = {started = t, count = 0, last = budget and budget.last or -math.huge}
        self.lookupBudget = budget
    end
    if not interactive and (budget.count >= LOOKUP_PER_MINUTE
        or t - budget.last < LOOKUP_MIN_INTERVAL) then
        self:BumpNetworkStat("deferredLookups")
        return false, "budget"
    end
    budget.count, budget.last = budget.count + 1, t
    local id = self:NewRequestID()
    local pending = {id = id, guid = target.guid, target = target,
        expires = t + self.QUERY_SECONDS, votes = {}, revisions = {},
        seeded = {}, seedCount = 0, responseCount = 0, interactive = interactive and true or nil}
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
    -- The own vote above was captured when the lookup started; if the player
    -- removed or changed their rating meanwhile, use the current one instead.
    if self.SyncOwnCachedVote then self:SyncOwnCachedVote(guid) end
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
    -- A real reply to our lookup makes the sender a proven peer.
    self:RememberPeer(sender, "proven")
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
        self:RememberPeer(canonical, "greeting")
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
        self:RememberPeer(canonical, "greeting")
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
    C_Timer.NewTicker(0.5, function() self:ProcessLookupQueue() end)
    C_Timer.NewTicker(15, function() self:PruneInbound(); self:PruneReviewTags(); self:PruneSharedLookups(); self:EnsureBroadcastChannel() end)
    C_Timer.After(3 + jitter(1.5), function() self:Discovery(); self:OnGroupRosterUpdate() end)
end

