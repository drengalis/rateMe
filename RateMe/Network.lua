local _, A = ...

local PREFIX = "RATEME"
local MAX_QUEUE = 180
local MAX_HOPS = 2
local MAX_FANOUT = 3
local MAX_COMMENT_REQUESTS = 20
local CHUNK_DELAY = 0.35 -- <= 3 messages/sec, before server throttling

local function fields(value, limit)
    local out = {}
    local start = 1
    for i = 1, limit - 1 do
        local at = value:find("|", start, true)
        if not at then break end
        out[#out + 1] = value:sub(start, at - 1)
        start = at + 1
    end
    out[#out + 1] = value:sub(start)
    return out
end
local function validId(id)
    return type(id) == "string" and #id >= 2 and #id <= 25 and id:match("^[%w%-]+$") ~= nil
end
local function validGuid(guid)
    return type(guid) == "string" and #guid <= 64 and guid:match("^Player%-%x+%-%x+$") ~= nil
end

function A:QueueSend(message, channel, target, logged)
    if type(message) ~= "string" or #message > 255 or #message == 0 then return false end
    if type(channel) ~= "string" then return false end
    if channel == "WHISPER" then
        target = self:CleanName(target)
        if not target or self:Key(target) == self:Key(self.myName) then return false end
    end
    -- Never silently fall back to unlogged transmission for user-written reviews.
    if logged and (not C_ChatInfo or type(C_ChatInfo.SendAddonMessageLogged) ~= "function") then
        self:Debug("Logged comment transport is unavailable; comment not sent.")
        return false
    end
    if #self.outbox >= MAX_QUEUE then return false end
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
    local fn = job.logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
    if type(fn) ~= "function" then
        self:Debug("Requested addon transport unavailable; message dropped safely.")
        return
    end
    local ok, result = pcall(fn, PREFIX, job.message, job.channel, job.target)
    -- New clients return Enum.SendAddonMessageResult; older clients may return nil.
    local throttled = ok and (result == 3 or
        (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.AddonMessageThrottle))
    if throttled and job.retries < 3 then
        job.retries = job.retries + 1
        job.due = self:Now() + (2 ^ job.retries)
        self.outbox[#self.outbox + 1] = job
    elseif not ok then
        self:Debug("Send error: " .. tostring(result))
    elseif result ~= nil and result ~= 0 and result ~= true and not throttled then
        self:Debug("Message rejected: " .. tostring(result))
    end
    self.nextSend = self:Now() + CHUNK_DELAY
end

function A:UnderInboundLimit(sender, kind, cap, seconds)
    self.inbound = self.inbound or {}
    local key = (self:Key(sender) or "unknown") .. ":" .. kind
    local now = self:Now()
    local item = self.inbound[key]
    if not item or now - item.started >= seconds then
        self.inbound[key] = {started = now, count = 1}
        return true
    end
    if item.count >= cap then return false end
    item.count = item.count + 1
    return true
end

function A:RememberPeer(name)
    local key = self:Key(name)
    if not key or key == self:Key(self.myName) then return end
    local item = self.db.peers[key] or {}
    item.name = self:CleanName(name)
    item.seen = self:Stamp()
    self.db.peers[key] = item
    -- Cap peer directory, avoiding unbounded SavedVariables growth.
    local count = 0
    for _ in pairs(self.db.peers) do count = count + 1 end
    if count > 120 then
        local oldestKey, timestamp = nil, math.huge
        for k, p in pairs(self.db.peers) do
            if (p.seen or 0) < timestamp then timestamp, oldestKey = p.seen or 0, k end
        end
        if oldestKey then self.db.peers[oldestKey] = nil end
    end
end

function A:PeerNames(exclude, maximum)
    local sorted = {}
    local cutoff = self:Stamp() - 24 * 3600
    for key, peer in pairs(self.db.peers) do
        if peer.seen and peer.seen >= cutoff and peer.name and key ~= self:Key(exclude)
            and key ~= self:Key(self.myName) then
            sorted[#sorted + 1] = peer
        end
    end
    table.sort(sorted, function(x, y) return (x.seen or 0) > (y.seen or 0) end)
    local result = {}
    for i = 1, math.min(maximum or #sorted, #sorted) do result[#result + 1] = sorted[i].name end
    return result
end

function A:Discovery()
    if self:Now() - (self.lastHello or -1000) < 90 then return end
    self.lastHello = self:Now()
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        self:QueueSend("H|" .. self.protocol, "INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then
        self:QueueSend("H|" .. self.protocol, "RAID")
    elseif IsInGroup and IsInGroup() then
        self:QueueSend("H|" .. self.protocol, "PARTY")
    end
    if IsInGuild and IsInGuild() then self:QueueSend("H|" .. self.protocol, "GUILD") end
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

function A:Query(target, force)
    if not self:ValidateStoredTarget(target) then return false end
    self:RememberTarget(target)
    local c = self.runtime.cache[target.guid]
    local t = self:Now()
    if not force and c and c.fetchedAt and t - c.fetchedAt < self.CACHE_SECONDS then return false end
    if c and c.queryUntil and t < c.queryUntil then return false end
    if self:ActiveQueries() >= self.MAX_PENDING then return false end
    local id = self:NewRequestID()
    local pending = {id = id, guid = target.guid, target = target, expires = t + self.QUERY_SECONDS, votes = {}}
    -- Include the reviewer's own locally authenticated vote in this request's sample.
    local own = self:GetOwnRating(target.guid)
    if own and not own.removed and own.faction == self.myFaction and own.score >= 1 and own.score <= 5 then
        pending.votes[self:Key(self.myName)] = {
            sender = self.myName, score = own.score, date = own.date,
            rev = own.rev, hasComment = own.comment and own.comment ~= "",
            comment = own.comment or "",
        }
    end
    self.runtime.requests[id] = pending
    c = c or {votes = {}}
    c.queryUntil = t + self.QUERY_SECONDS
    self.runtime.cache[target.guid] = c
    -- Begin a new sample; earlier votes do not remain part of a newly verified result.
    local packet = table.concat({"Q", id, target.guid, self.myName, tostring(MAX_HOPS)}, "|")
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        self:QueueSend(packet, "INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then
        self:QueueSend(packet, "RAID")
    elseif IsInGroup and IsInGroup() then
        self:QueueSend(packet, "PARTY")
    end
    if IsInGuild and IsInGuild() then self:QueueSend(packet, "GUILD") end
    for _, peer in ipairs(self:PeerNames(nil, 3)) do self:QueueSend(packet, "WHISPER", peer) end
    C_Timer.After(self.QUERY_SECONDS + 0.2, function()
        if self.runtime.requests[id] then self:FinishQuery(id) end
    end)
    self:NotifyUI()
    return true
end

function A:FinishQuery(id)
    local request = self.runtime.requests[id]
    if not request then return end
    self.runtime.requests[id] = nil
    local target, guid = request.target, request.guid
    local cache = self.runtime.cache[guid] or {}
    cache.votes = request.votes
    cache.fetchedAt = self:Now()
    cache.queryUntil = nil
    cache.lastComplete = self:Stamp()
    self.runtime.cache[guid] = cache
    local summary = self:GetSummary(guid)
    self:RememberTarget(target)
    local recent = self.db.recent[guid]
    if recent then
        recent.average = summary and summary.average or nil
        recent.count = summary and summary.count or 0
        recent.comments = summary and summary.comments or 0
        recent.checked = self:Stamp()
    end
    self:NotifyUI()
    if self.reviews and self.reviews:IsShown() and self.reviews.target
        and self.reviews.target.guid == guid then
        self:RequestComments(guid)
        self:NotifyUI()
    end
    self:RefreshTooltip(guid)
    if self.RefreshHighlights then self:RefreshHighlights() end
    if self.OnRatingQueryComplete then self:OnRatingQueryComplete(guid) end
end

function A:RequestComments(guid)
    local cache = self.runtime.cache[guid]
    if not cache or not cache.votes then return 0 end
    local sent = 0
    local t = self:Now()
    for key, vote in pairs(cache.votes) do
        if sent >= MAX_COMMENT_REQUESTS then break end
        if not self.db.ignored[key] and vote.hasComment and not vote.comment
            and not (vote.commentRequested and t - vote.commentRequested < 60) then
            local id = self:NewRequestID()
            self.runtime.comments[id] = {guid = guid, reviewer = key, expires = t + 15}
            vote.commentRequested = t
            if self:QueueSend(table.concat({"C?", id, guid}, "|"), "WHISPER", vote.sender) then
                sent = sent + 1
            else
                self.runtime.comments[id] = nil
            end
        end
    end
    return sent
end

function A:HandleQuery(args, sender)
    if #args ~= 5 or not self:UnderInboundLimit(sender, "Q", 6, 20) then return end
    local id, guid, origin, hops = args[2], args[3], self:CleanName(args[4]), tonumber(args[5])
    if not validId(id) or not validGuid(guid) or not origin or not hops or hops < 0 or hops > MAX_HOPS then return end
    local seenKey = id .. ":" .. self:Key(origin)
    if self.runtime.seen[seenKey] and self.runtime.seen[seenKey] > self:Now() then return end
    self.runtime.seen[seenKey] = self:Now() + 30
    local record = self:GetOwnRating(guid)
    if record and record.faction == self.myFaction and self:Key(origin) ~= self:Key(self.myName) then
        local value = record.removed and 0 or tonumber(record.score)
        if value and value >= 0 and value <= 5 then
            self:QueueSend(table.concat({"R", id, guid, value, record.rev or 1,
                record.date or self:Stamp(), (record.comment and #record.comment > 0) and 1 or 0}, "|"), "WHISPER", origin)
        end
    end
    if hops <= 0 then return end
    local count = 0
    local packet = table.concat({"Q", id, guid, origin, hops - 1}, "|")
    for _, peer in ipairs(self:PeerNames(sender, 8)) do
        if self:Key(peer) ~= self:Key(origin) and count < MAX_FANOUT then
            if self:QueueSend(packet, "WHISPER", peer) then count = count + 1 end
        end
    end
end

function A:HandleRating(args, sender)
    if #args ~= 7 then return end
    local id, guid, score, revision, date, hasComment = args[2], args[3], tonumber(args[4]),
        tonumber(args[5]), tonumber(args[6]), tonumber(args[7])
    local request = id and self.runtime.requests[id]
    if not request or request.expires < self:Now() or request.guid ~= guid then return end
    if not score or score ~= math.floor(score) or score < 0 or score > 5 then return end
    if not revision or revision ~= math.floor(revision) or revision < 1 or revision > 100000000 then return end
    if not date or date < 0 or date > 5000000000 or (hasComment ~= 0 and hasComment ~= 1) then return end
    local key = self:Key(sender)
    if not key or key == self:Key(self.myName) then return end
    local existing = request.votes[key]
    if existing and existing.rev >= revision then return end
    if score == 0 then
        request.votes[key] = nil
    else
        request.votes[key] = {score = score, rev = revision, date = date, hasComment = hasComment == 1,
            sender = self:CleanName(sender)}
    end
    self:NotifyUI()
end

function A:HandleCommentRequest(args, sender)
    if #args ~= 3 or not validId(args[2]) or not validGuid(args[3])
        or not self:UnderInboundLimit(sender, "C?", 4, 30) then return end
    local record = self:GetOwnRating(args[3])
    if not record or record.removed or not record.comment or record.comment == "" then return end
    local message = table.concat({"C", args[2], args[3], record.rev or 1, self:SanitizeComment(record.comment)}, "|")
    self:QueueSend(message, "WHISPER", sender, true)
end

function A:HandleComment(args, sender, logged, rawMessage)
    if #args ~= 5 or not logged then return end
    local id, guid, revision = args[2], args[3], tonumber(args[4])
    local pending = id and self.runtime.comments[id]
    if not pending or pending.expires < self:Now() or pending.guid ~= guid
        or pending.reviewer ~= self:Key(sender) then return end
    if self.db.ignored[pending.reviewer] then self.runtime.comments[id] = nil; return end
    local cache = self.runtime.cache[guid]
    local vote = cache and cache.votes[self:Key(sender)]
    if not vote or not vote.hasComment or vote.rev ~= revision then return end
    -- The direct rating sender and logged comment sender must be identical.
    -- Never accept an author identity carried in a comment payload or from a relay.
    local author = self:CleanName(sender)
    if not author or self:Key(vote.sender) ~= self:Key(author) then return end
    if #args[5] == 0 or #args[5] > self.MAX_COMMENT or args[5]:find("[%c|]")
        or type(rawMessage) ~= "string" then return end
    local safeComment = self:SanitizeComment(args[5])
    if safeComment == "" then return end
    self.runtime.comments[id] = nil
    vote.comment = safeComment
    -- Store evidence from CHAT_MSG_ADDON_LOGGED rather than an editable rater
    -- field in the packet. Only this captured sender can be reported.
    vote.commentSource = {
        sender = author, targetGUID = guid, revision = revision,
        receivedAt = self:Stamp(), logged = true,
        payload = rawMessage,
    }
    self:NotifyUI()
end

function A:OnMessage(prefix, message, channel, sender, logged)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 255 then return end
    local canonical = self:CleanName(sender)
    if not canonical or self:Key(canonical) == self:Key(self.myName) then return end
    if type(channel) ~= "string" then return end
    local tag = message:match("^([^|]+)")
    if logged and tag ~= "C" then return end
    if not logged and tag == "C" then return end
    if tag == "H" and message == "H|" .. self.protocol then
        local key = self:Key(canonical)
        local prior = self.db.peers[key]
        local recently = prior and prior.hello and self:Stamp() - prior.hello < 120
        self:RememberPeer(canonical)
        if not recently then
            self.db.peers[key].hello = self:Stamp()
            self:QueueSend("A|" .. self.protocol, "WHISPER", canonical)
            local names = self:PeerNames(canonical, 2)
            if #names > 0 then self:QueueSend("P|" .. table.concat(names, ","), "WHISPER", canonical) end
        end
    elseif tag == "A" and message == "A|" .. self.protocol then
        self:RememberPeer(canonical)
    elseif tag == "P" and channel == "WHISPER" then
        -- Introductions aren't votes or verified identities. Probe independently.
        if not self.db.peers[self:Key(canonical)] then return end
        local payload = message:sub(3)
        if #payload > 180 then return end
        local count = 0
        for peer in payload:gmatch("[^,]+") do
            if count >= 2 then break end
            if self:Key(peer) and self:Key(peer) ~= self:Key(self.myName)
                and not self.db.peers[self:Key(peer)]
                and self:UnderInboundLimit(self.myName, "introductions", 8, 900) then
                self:QueueSend("H|" .. self.protocol, "WHISPER", peer)
                count = count + 1
            end
        end
    elseif tag == "Q" then
        self:RememberPeer(canonical)
        self:HandleQuery(fields(message, 5), canonical)
    elseif tag == "R" and channel == "WHISPER" then
        self:RememberPeer(canonical)
        self:HandleRating(fields(message, 7), canonical)
    elseif tag == "C?" and channel == "WHISPER" then
        self:HandleCommentRequest(fields(message, 3), canonical)
    elseif tag == "C" and channel == "WHISPER" then
        self:HandleComment(fields(message, 5), canonical, logged, message)
    end
end

function A:InitializeNetwork()
    self.outbox, self.nextSend, self.counter = {}, 0, 0
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then
        self:Log("Addon messaging API not available. Local ratings still work.")
        return
    end
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
    if registered == false then self:Log("Unable to register addon message prefix.") end
    self.netFrame = CreateFrame("Frame")
    self.netFrame:RegisterEvent("CHAT_MSG_ADDON")
    self.netFrame:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
    self.netFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.netFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
    self.netFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
            A:OnMessage(select(1, ...), select(2, ...), select(3, ...), select(4, ...), event == "CHAT_MSG_ADDON_LOGGED")
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
            A:Discovery()
            if event == "GROUP_ROSTER_UPDATE" then A:OnGroupRosterUpdate() end
        end
    end)
    C_Timer.NewTicker(CHUNK_DELAY, function()
        self:FlushMessages()
        for id, item in pairs(self.runtime.comments) do
            if item.expires < self:Now() then self.runtime.comments[id] = nil end
        end
        for id, deadline in pairs(self.runtime.seen) do
            if deadline < self:Now() then self.runtime.seen[id] = nil end
        end
    end)
    C_Timer.After(3, function() self:Discovery(); self:OnGroupRosterUpdate() end)
end

