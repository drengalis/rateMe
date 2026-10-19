local _, Communication = ...
local A = Communication.API
local MAX_ROUTES, MAX_SEEN, MAX_REVIEWS, MAX_SHARED_RESULTS = 32, 256, 100, 100

function A:PruneSharedLookups()
    for id,route in pairs(self.sharedRoutes or {}) do
        if route.expires<self:Now() then self.sharedRoutes[id]=nil end
    end
    for id,expires in pairs(self.sharedLookupSeen or {}) do
        if expires<self:Now() then self.sharedLookupSeen[id]=nil end
    end
end

function A:SendSharedReview(route, vote)
    local key=self:Key(vote.sender)
    if not key or key==self:Key(route.parent) or route.sentCount>=MAX_REVIEWS then return false end
    local prior=route.sent[key]
    if prior and (prior.rev>vote.rev or (prior.rev==vote.rev and prior.score==vote.score and prior.tags==vote.tags)) then return false end
    local packet=self.payload:SharedReview(route.parentID,route.target.guid,vote)
    if self:QueueSend(packet,"WHISPER",route.parent) then
        route.sent[key]={rev=vote.rev,score=vote.score,tags=vote.tags}
        route.sentCount=route.sentCount+1
        return true
    end
    return false
end

function A:HandleSharedLookup(args, sender)
    local id,target,hops=self.payload:SharedLookupFields(args)
    if not id or not self:ValidateStoredTarget(target) then return end
    if not self:UnderInboundLimit(sender,"sharedLookup",6,20) then return end
    self:PruneSharedLookups()
    self.sharedLookupSeen,self.sharedRoutes=self.sharedLookupSeen or {},self.sharedRoutes or {}
    local seen=self:Key(sender).."|"..id.."|"..target.guid
    if self.sharedLookupSeen[seen] then return end
    local seenCount,routeCount=0,0
    for _ in pairs(self.sharedLookupSeen) do seenCount=seenCount+1 end
    for _ in pairs(self.sharedRoutes) do routeCount=routeCount+1 end
    if seenCount>=MAX_SEEN or routeCount>=MAX_ROUTES then return end
    self.sharedLookupSeen[seen]=self:Now()+45
    local branch=self:NewRequestID()
    local route={parent=sender,parentID=id,target=target,expires=self:Now()+self.QUERY_SECONDS,
        children={},sent={},sentCount=0}
    -- Reply immediately, then stream merged results from child peers as they arrive.
    local records=self:CommunityReviewsForSharing(target.guid)
    local keys={}
    for key in pairs(records) do keys[#keys+1]=key end
    table.sort(keys,function(x,y)
        local a,b=self:IsCommunityReviewVerified(records[x]),self:IsCommunityReviewVerified(records[y])
        if a~=b then return a end
        return x<y
    end)
    for _,key in ipairs(keys) do self:SendSharedReview(route,records[key]) end
    if hops>0 then
        for _,peer in ipairs(self:SelectQueryPeers(branch,sender,sender,3)) do
            if self:QueueSend(self.payload:SharedLookup(branch,target,hops-1),"WHISPER",peer) then
                route.children[self:Key(peer)]=true
            end
        end
        if next(route.children) then self.sharedRoutes[branch]=route end
    end
    self:Debug("Shared saved reviews for "..self:DisplayName(target.name).." with "..self:DisplayName(sender)..".")
end

function A:HandleSharedReview(args, sender)
    local id,guid,vote=self.payload:SharedReviewFields(args)
    if not id then return end
    local peer=self:Key(sender)
    local request=self.runtime.requests[id]
    local route=self.sharedRoutes and self.sharedRoutes[id]
    local target
    if request and request.expires>=self:Now() and request.guid==guid
        and request.seeded and request.seeded[peer] then
        target=request.target
        request.sharedAuthors=request.sharedAuthors or {}
        request.sharedCount=request.sharedCount or 0
    elseif route and route.expires>=self:Now() and route.target.guid==guid and route.children[peer] then
        target=route.target
        request=nil
    else return end
    local author=self:Key(vote.sender)
    if not author or author==self:Key(self.myName) then return end
    local direct=author==peer
    if request and not request.sharedAuthors[author] and request.sharedCount>=MAX_SHARED_RESULTS then return end
    local accepted
    if direct then
        vote.freshAt=self:Now()
        accepted=self:SaveCommunityRating(target,author,vote)
    else
        accepted=self:SaveRelayedCommunityRating(target,author,vote,sender)
    end
    if not accepted then return end
    if direct then self:RememberPeer(sender) end
    self:RememberTarget(target)
    local cache=self.runtime.cache[guid] or {votes={}}
    cache.votes[author]=vote.score>0 and vote or nil
    cache.lastComplete=self:Stamp()
    self.runtime.cache[guid]=cache
    -- If a direct reply was already queued for this lookup, keep its sample in sync.
    for _,active in pairs(self.runtime.requests) do
        if active.guid==guid and active.revisions[author] and direct then
            active.revisions[author]=vote.rev
            active.votes[author]=vote.score>0 and vote or nil
        end
    end
    if request and not request.sharedAuthors[author] then
        request.sharedAuthors[author]=true
        request.sharedCount=request.sharedCount+1
    end
    self:SaveLookupSummary(guid,self:GetSummary(guid))
    if route and not request then self:SendSharedReview(route,vote) end
    self:BumpNetworkStat("sharedReviewsAccepted")
    self:Debug("Saved "..(direct and "an author-verified review" or "a peer-supplied review").." by "
        ..self:DisplayName(vote.sender).." for "..self:DisplayName(target.name)..".")
    self:NotifyUI()
    self:RefreshTooltip(guid)
    if direct and self.RefreshHighlights then self:RefreshHighlights() end
    if direct and self.OnRatingQueryComplete then self:OnRatingQueryComplete(guid) end
end
