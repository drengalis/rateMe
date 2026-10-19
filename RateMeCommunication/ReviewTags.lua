local _, Communication = ...
local A = Communication.API

function A:HandleReviewTags(args, sender)
    local request,guid,revision,tags=self.payload:ReviewTagFields(args)
    if not request then return end
    if request=="-" then
        if not self.db.settings.receiveRatingBroadcasts then return end
    else
        local context=self.runtime.requests[request] or (self.tagQueryHistory and self.tagQueryHistory[request])
        if not context or context.guid~=guid or context.expires<self:Now() then return end
    end
    if not self:UnderInboundLimit(sender,"tags",18,30) then return end
    local key=self:Key(sender)
    local item=self.db.community[guid]
    local vote=item and item.votes[key]
    if vote and vote.rev==revision and vote.score>0 and self:IsCommunityReviewVerified(vote) then
        if self:SaveCommunityTags(guid,key,revision,tags) then
            local cache=self.runtime.cache[guid]
            if cache and cache.votes[key] and cache.votes[key].rev==revision then cache.votes[key].tags=tags end
            for _,query in pairs(self.runtime.requests) do
                if query.guid==guid and query.votes[key] and query.votes[key].rev==revision then
                    query.votes[key].tags=tags
                end
            end
            self:NotifyUI()
        end
        return
    end
    if vote and vote.rev>=revision then return end
    -- Accept out-of-order metadata only into a bounded, short-lived buffer.
    self.pendingReviewTags=self.pendingReviewTags or {}
    self:PruneReviewTags()
    local count=0
    for _ in pairs(self.pendingReviewTags) do count=count+1 end
    local pendingKey=guid.."|"..key
    local existing=self.pendingReviewTags[pendingKey]
    if existing and existing.rev>revision then return end
    if count>=128 and not existing then return end
    self.pendingReviewTags[pendingKey]={rev=revision,tags=tags,expires=self:Now()+15}
end

function A:ApplyPendingReviewTags(guid, key, vote)
    local id=guid.."|"..key
    local pending=self.pendingReviewTags and self.pendingReviewTags[id]
    if pending and pending.expires>=self:Now() and pending.rev==vote.rev and vote.score>0 then
        if self:SaveCommunityTags(guid,key,vote.rev,pending.tags) then vote.tags=pending.tags end
    end
    if self.pendingReviewTags then self.pendingReviewTags[id]=nil end
end

function A:PruneReviewTags()
    for id,item in pairs(self.pendingReviewTags or {}) do
        if item.expires<self:Now() then self.pendingReviewTags[id]=nil end
    end
    for id,item in pairs(self.tagQueryHistory or {}) do
        if item.expires<self:Now() then self.tagQueryHistory[id]=nil end
    end
end
