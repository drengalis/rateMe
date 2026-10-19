-- Storage class implemented by RateMeData; bound into the RateMe interface for existing callers.
local _, Store = ...
local A = Store.API

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
    local summary = self:GetSummary(guid)
    if summary and summary.fresh and summary.average and summary.count > 0 then
        return summary.average, summary.count
    end
    return nil
end


function A:GetSummary(guid)
    local cache = self.runtime.cache[guid]
    if cache then
        local total, count, withComments = 0, 0, 0
        for _, v in pairs(cache.votes) do
            if v.score >= 1 and v.score <= 5 then
                total, count = total + v.score, count + 1
                if v.hasComment then withComments = withComments + 1 end
            end
        end
        local age = self:Now() - (cache.fetchedAt or 0)
        return { average = count > 0 and total / count or nil, count = count,
            comments = withComments, fresh = age < self.CACHE_SECONDS,
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
    local recent = self.data.recent[guid]
    if not recent then return end
    recent.average = summary and summary.average or nil
    recent.count = summary and summary.count or 0
    recent.comments = summary and summary.comments or 0
    recent.checked = self:Stamp()
end
