-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

-- Persist data only, never monotonic timers, pending requests or report evidence.
local function copyVote(v)
    return {sender=v.sender, score=v.score, rev=v.rev, date=v.date,
        tags=v.tags, verifiedAt=v.verifiedAt, receivedAt=v.receivedAt, via=v.via}
end

function A:RestoreCommunityLookups()
    for guid, item in pairs(self.db.community) do
        if type(item) == "table" and item.faction == self.myFaction
            and type(item.votes) == "table" then
            local cache = {votes={}, lastComplete=item.checked or 0}
            for key, vote in pairs(item.votes) do
                if type(vote) == "table" and type(vote.score) == "number"
                    and vote.score >= 1 and vote.score <= 5 then
                    cache.votes[key] = copyVote(vote)
                end
            end
            self.runtime.cache[guid] = cache
        end
    end
end

-- Protocol 1 authenticates reviewer sender names, not reviewer GUIDs.
function A:SaveCommunityRating(target, reviewer, vote)
    if not self:ValidateStoredTarget(target) then return false end
    local item = self.db.community[target.guid]
    if not item then
        item = {guid=target.guid, name=target.name, faction=target.faction,
            class=target.class, votes={}}
        self.db.community[target.guid] = item
    end
    local prior = item.votes[reviewer]
    local priorVerified = prior and self:IsCommunityReviewVerified(prior)
    -- A direct author can correct an unverified peer copy even at a lower revision.
    if priorVerified and prior.rev > vote.rev then return false end
    if priorVerified and prior.rev == vote.rev then
        if prior.score ~= vote.score or prior.date ~= vote.date
            or (prior.tags~=nil and vote.tags~=nil and prior.tags~=vote.tags) then return false end
        vote.tags = vote.tags or prior.tags
    end
    vote.verifiedAt = self:Stamp()
    vote.receivedAt, vote.via = nil, nil
    item.votes[reviewer] = copyVote(vote)
    return true
end

-- Relayed copies never inherit the sender's or another peer's verified flag.
-- Directly verified records are authoritative locally, including deletions.
function A:SaveRelayedCommunityRating(target, reviewer, vote, relay)
    if not self:ValidateStoredTarget(target) or reviewer == self:Key(self.myName) then return false end
    local item=self.db.community[target.guid]
    if not item then
        item={guid=target.guid,name=target.name,faction=target.faction,class=target.class,votes={}}
        self.db.community[target.guid]=item
    end
    local prior=item.votes[reviewer]
    if prior and self:IsCommunityReviewVerified(prior) then return false end
    if prior and prior.rev>vote.rev then return false end
    if prior and prior.rev==vote.rev then
        if prior.score~=vote.score or prior.date~=vote.date then return false end
        if prior.tags~=nil and vote.tags~=nil and prior.tags~=vote.tags then return false end
        if prior.tags~=nil or vote.tags==nil then return false end
    end
    vote.verifiedAt,vote.freshAt=nil,nil
    vote.receivedAt,vote.via=self:Stamp(),self:CleanName(relay)
    item.votes[reviewer]=copyVote(vote)
    return true
end

function A:CommunityReviewsForSharing(guid)
    local result={}
    local ownKey=self:Key(self.myName)
    local item=self.db.community[guid]
    if item and item.faction==self.myFaction then
        for key,vote in pairs(item.votes) do
            if key~=ownKey then result[key]=copyVote(vote) end
        end
    end
    local own=self:GetOwnRating(guid)
    if own and own.faction==self.myFaction then
        result[ownKey]={sender=self.myName,score=own.removed and 0 or own.score,
            rev=own.rev,date=own.date,tags=own.tags}
    end
    return result
end

function A:SaveCommunityTags(guid, reviewer, revision, tags)
    local item = self.db.community[guid]
    local vote = item and item.votes[reviewer]
    local encoded = self:EncodeReviewTags(tags)
    if not vote or vote.score == 0 or vote.rev ~= revision or not encoded then return false end
    -- Equal revisions are immutable once their complete tag set is known.
    if vote.tags ~= nil and vote.tags ~= encoded then return false end
    vote.tags = encoded
    return true
end

-- Authorship verification survives reloads; freshness is a separate session flag.
-- verifiedAt is assigned only after a validated direct-author response.
function A:IsCommunityReviewVerified(vote)
    return type(vote) == "table" and type(vote.verifiedAt) == "number"
        and vote.verifiedAt > 0 and type(vote.sender) == "string"
end

function A:RememberTarget(target)
    if not self:ValidateStoredTarget(target) then return end
    local recent = self.data.recent
    local item = recent[target.guid] or {}
    item.guid, item.name, item.faction, item.class = target.guid, target.name, target.faction, target.class
    item.viewed = self:Stamp()
    recent[target.guid] = item
    local count = 0
    for _ in pairs(recent) do count = count + 1 end
    while count > self.MAX_RECENT do
        local oldestKey, oldest = nil, math.huge
        for guid, entry in pairs(recent) do
            if (entry.viewed or 0) < oldest then oldest = entry.viewed or 0; oldestKey = guid end
        end
        if not oldestKey then break end
        recent[oldestKey] = nil
        count = count - 1
    end
end


function A:GetFreshCommunityScore(guid)
    local cache = self.runtime.cache[guid]
    local total, count = 0, 0
    for _, vote in pairs(cache and cache.votes or {}) do
        if (self:IsCommunityReviewVerified(vote) or self:Key(vote.sender)==self:Key(self.myName)) and vote.freshAt and self:Now() - vote.freshAt < self.CACHE_SECONDS then
            total, count = total + vote.score, count + 1
        end
    end
    if count > 0 then return total / count, count end
end


function A:GetSummary(guid)
    local cache = self.runtime.cache[guid]
    if cache then
        local total, count, withTags, freshCount, peerCount = 0, 0, 0, 0, 0
        for _, v in pairs(cache.votes) do
            if v.score >= 1 and v.score <= 5 then
                total, count = total + v.score, count + 1
                if v.via and not self:IsCommunityReviewVerified(v) then peerCount=peerCount+1 end
                if v.tags and v.tags ~= "" then withTags = withTags + 1 end
                if (self:IsCommunityReviewVerified(v) or self:Key(v.sender)==self:Key(self.myName)) and v.freshAt and self:Now() - v.freshAt < self.CACHE_SECONDS then
                    freshCount = freshCount + 1
                end
            end
        end
        local age = self:Stamp() - (cache.lastComplete or 0)
        return { average = count > 0 and total / count or nil, count = count,
            tagged = withTags, fresh = count > 0 and freshCount == count,
            freshCount = freshCount, cachedCount = count - freshCount, peerCount = peerCount,
            age = math.max(0, age), at = cache.lastComplete or 0 }
    end
    local prior = self.data.recent[guid]
    if prior and prior.checked and prior.checked > 0 then
        return { average = prior.average, count = prior.count or 0, tagged = prior.tagged or 0,
            fresh = false, at = prior.checked, historical = true }
    end
    return nil
end


function A:ListRecent()
    local list = {}
    for guid, entry in pairs(self.data.recent) do
        if entry.faction == self.myFaction and guid ~= self.myGuid then
            local item = {}
            for k, v in pairs(entry) do item[k] = v end
            local summary = self:GetSummary(guid)
            item.score = summary and summary.average or nil
            item.count = summary and summary.count or 0
            item.fresh = summary and summary.fresh or false
            table.insert(list, item)
        end
    end
    return list
end

function A:SaveLookupSummary(guid, summary)
    local item = self.db.community[guid]
    if item then item.checked = self:Stamp() end
    local recent = self.data.recent[guid]
    if not recent then return end
    recent.average = summary and summary.average or nil
    recent.count = summary and summary.count or 0
    recent.tagged = summary and summary.tagged or 0
    recent.checked = self:Stamp()
end
