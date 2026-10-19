local root = ""
local files = io.popen("find RateMe RateMeData RateMeCommunication -name '*.lua'")
local syntax = 0
for path in files:lines() do assert(loadfile(path)); syntax=syntax+1 end
files:close()
local function boot()
    local store = {}
    for _, name in ipairs({"Store","Settings","Tags","Ratings","Community","Peers","Reviewers"}) do
        assert(loadfile(root.."RateMeData/"..name..".lua"))("RateMeData",store)
    end
    local a = {protocol="1", myName="Me",myGuid="Player-me",myFaction="Alliance",
        runtime={cache={},requests={},comments={},seen={}}, clock=10, epoch=1800000000}
    store:Bind(a)
    function a:Now() return self.clock end
    function a:Stamp() return self.epoch end
    function a:Key(n) return n and n:lower() end
    function a:CleanName(n) return n end
    function a:DisplayName(n) return n end
    function a:ValidateStoredTarget(t) return t.faction==self.myFaction end
    a:InitializeStorage()
    local communication={}
    for _, name in ipairs({"Store","Payload","Diagnostics","Broadcasts","ReviewTags","SharedReviews","Network"}) do
        assert(loadfile(root.."RateMeCommunication/"..name..".lua"))("RateMeCommunication",communication)
    end
    communication:Bind(a)
    a.payload={}
    function a.payload:RatingFields(args) return table.unpack(args) end
    function a.payload:CommentFields(args) return table.unpack(args) end
    function a:NotifyUI() end
    function a:RefreshTooltip() end
    function a:BumpNetworkStat() end
    function a:Debug() end
    return a
end
local a=boot()
local target={guid="Player-target", name="Target", faction="Alliance"}
local function start(id)
    a.runtime.requests[id]={target=target,guid=target.guid,expires=999,votes={},
        revisions={},responseCount=0}
end
local function reply(id,who,score,rev,date,comment)
    a:HandleRating({id,target.guid,score,rev,date or 100,comment or 0},who)
end
local function cache() return a.runtime.cache[target.guid] end
start("one")
reply("one","Alice",5,1,100,1)
reply("one","Bob",3,1)
assert(a.db.community[target.guid].votes.alice.score==5) -- saved before completion
a:FinishQuery("one")
assert(a:GetSummary(target.guid).count==2)
assert(a:GetFreshCommunityScore(target.guid)==4)
local encoded=a:EncodeReviewTags({1,7})
assert(a:SaveCommunityTags(target.guid,"alice",1,encoded))
cache().votes.alice.tags=encoded
assert(a.db.community[target.guid].votes.alice.tags==encoded)
assert(a.db.community[target.guid].votes.alice.comment==nil)
assert(a.db.community[target.guid].votes.alice.freshAt==nil)
assert(a:IsCommunityReviewVerified(cache().votes.alice))
assert(not a:IsCommunityReviewVerified({sender="Other",score=5}))
assert(not a:IsCommunityReviewVerified({sender="Other",verifiedAt=0}))
local function literal(value)
    if type(value)=="table" then
        local fields={}
        for k,v in pairs(value) do fields[#fields+1]="["..literal(k).."]="..literal(v) end
        return "{"..table.concat(fields,",").."}"
    end
    if type(value)=="string" then return string.format("%q",value) end
    return tostring(value)
end
-- Exercise a SavedVariables-style Lua serialization round trip.
RateMeDB=assert(load("return "..literal(RateMeDB)))()
-- A new instance has no session timers/evidence. Persisted table survives.
a=boot()
assert(a:GetSummary(target.guid).count==2)
assert(not a:GetSummary(target.guid).fresh)
assert(a:IsCommunityReviewVerified(cache().votes.alice)) -- cached does not mean unverified
assert(a:GetFreshCommunityScore(target.guid)==nil)
assert(cache().votes.alice.tags==encoded)
assert(cache().votes.alice.commentSource==nil)
start("two")
reply("two","Alice",5,1,100,1)
a:FinishQuery("two")
assert(a:GetSummary(target.guid).count==2) -- missing Bob retained
assert(a:GetSummary(target.guid).freshCount==1)
assert(a:GetSummary(target.guid).cachedCount==1)
assert(a:GetFreshCommunityScore(target.guid)==5) -- stale Bob excluded
assert(cache().votes.alice.tags==encoded)
start("three")
reply("three","Alice",2,2,200,1)
a:FinishQuery("three")
assert(cache().votes.alice.tags==nil) -- old revision tags invalidated
start("four")
reply("four","Alice",0,3,300)
a:FinishQuery("four")
assert(cache().votes.alice==nil)
assert(a.db.community[target.guid].votes.alice.score==0)
a=boot()
start("five")
reply("five","Alice",5,2,200,1) -- old record cannot revive deletion
a:FinishQuery("five")
assert(cache().votes.alice==nil)
assert(a:GetSummary(target.guid).count==1)
start("six")
reply("six","Bob",1,1) -- conflicting equal revision rejected
a:FinishQuery("six")
assert(cache().votes.bob.score==3)
start("seven")
a:FinishQuery("seven")
assert(a:GetSummary(target.guid).count==1) -- empty lookup retains cache
-- Pruning Recent never deletes the durable review store.
a.MAX_RECENT=1
a:RememberTarget({guid="Player-other",name="Other",faction="Alliance"})
assert(a.db.community[target.guid].votes.bob.score==3)
print("PASS: "..syntax.." Lua syntax checks; persistence, merge, comments, freshness, deletions and replay regressions")
