-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

-- Persist data only, never monotonic timers, pending requests or report evidence.
local function copyVote(v)
    return {sender=v.sender, score=v.score, rev=v.rev, date=v.date,
        hasComment=v.hasComment, comment=v.comment, verifiedAt=v.verifiedAt}
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
    if prior and prior.rev > vote.rev then return false end
    if prior and prior.rev == vote.rev then
        if prior.score ~= vote.score or prior.date ~= vote.date
            or prior.hasComment ~= vote.hasComment then return false end
        vote.comment = prior.comment
    end
    vote.verifiedAt = self:Stamp()
    item.votes[reviewer] = copyVote(vote)
    return true
end

function A:SaveCommunityComment(guid, reviewer, vote)
    local item = self.db.community[guid]
    local prior = item and item.votes[reviewer]
    if prior and prior.score > 0 and prior.rev == vote.rev and prior.hasComment then
        prior.comment = vote.comment
    end
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
        if vote.freshAt and self:Now() - vote.freshAt < self.CACHE_SECONDS then
            total, count = total + vote.score, count + 1
        end
    end
    if count > 0 then return total / count, count end
end


function A:GetSummary(guid)
    local cache = self.runtime.cache[guid]
    if cache then
        local total, count, withComments, freshCount = 0, 0, 0, 0
        for _, v in pairs(cache.votes) do
            if v.score >= 1 and v.score <= 5 then
                total, count = total + v.score, count + 1
                if v.hasComment then withComments = withComments + 1 end
                if v.freshAt and self:Now() - v.freshAt < self.CACHE_SECONDS then
                    freshCount = freshCount + 1
                end
            end
        end
        local age = self:Stamp() - (cache.lastComplete or 0)
        return { average = count > 0 and total / count or nil, count = count,
            comments = withComments, fresh = count > 0 and freshCount == count,
            freshCount = freshCount, cachedCount = count - freshCount,
            age = math.max(0, age), at = cache.lastComplete or 0 }
    end
    local prior = self.data.recent[guid]
    if prior and prior.checked and prior.checked > 0 then
        return { average = prior.average, count = prior.count or 0, comments = prior.comments or 0,
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
    recent.comments = summary and summary.comments or 0
    recent.checked = self:Stamp()
end
