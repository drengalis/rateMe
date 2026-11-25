-- Rating scores: own-rating sync, personal and community sources, verified-only averages and their display.

-- Own rating kept in step with the community cache
do
-- Removing or changing a rating must update the cached copy of the player's own
-- vote at once, so highlights and badges never keep showing a removed rating.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
 function a:Now()return self.clock end
 function a:Stamp()return 1800000000+math.floor(self.clock)end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return n end
 function a:ValidateStoredTarget(t)return t.faction=='Alliance' and t.guid~=self.myGuid end
 function a:NotifyUI()end
 function a:RefreshTooltip()end
 function a:Log()end
 function a:Debug()end
 local store=dofile('tests/load_data_addon.lua');store:Bind(a)
 dofile('tests/load_communication_addon.lua')(a)
 a:InitializeStorage()
 a.outbox={};a.counter=0;a.nextSend=0;a.inbound={}
 return a
end

RateMeDB=nil
local timers={}
C_Timer={After=function(delay,fn)timers[#timers+1]={delay=delay,fn=fn}end,NewTicker=function()end}
local a=boot()
local refreshes=0
function a:RefreshHighlights()refreshes=refreshes+1 end
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
local ownKey=a:Key(a.myName)

-- A lookup records a fresh copy of the player's own vote in the runtime cache.
assert(a:SaveOwnRating(target,5,{}))
a.clock=10
assert(a:Query(target,false,true))
local id=next(a.runtime.requests)
a:FinishQuery(id)
assert(a.runtime.cache[target.guid].votes[ownKey].score==5)
assert(a:GetFreshCommunityScore(target.guid,true)==5)

-- Changing the rating replaces the cached copy straight away.
refreshes=0
assert(a:SaveOwnRating(target,1,{}))
assert(a.runtime.cache[target.guid].votes[ownKey].score==1,'cached own vote must follow an edit')
assert(a:GetFreshCommunityScore(target.guid,true)==1 and refreshes>=1)
print('PASS: editing a rating updates the cached own vote and refreshes highlights')

-- Removing the rating deletes the cached copy straight away.
refreshes=0
assert(a:DeleteOwnRating(target))
assert(a.runtime.cache[target.guid].votes[ownKey]==nil,'cached own vote must be removed')
assert(a:GetFreshCommunityScore(target.guid,true)==nil and refreshes>=1)
assert(a:GetPersonalScore(target.guid)==nil)
print('PASS: removing a rating clears the cached own vote and refreshes highlights')

-- A lookup that started before the removal must not bring the old vote back.
assert(a:SaveOwnRating(target,4,{}))
a.clock=2000
assert(a:Query(target,true,true))
id=next(a.runtime.requests)
assert(a.runtime.requests[id].votes[ownKey].score==4,'lookup captured the vote at start')
assert(a:DeleteOwnRating(target))
a:FinishQuery(id)
assert(a.runtime.cache[target.guid].votes[ownKey]==nil,'finished lookup must use the current (removed) rating')
assert(a:GetFreshCommunityScore(target.guid,true)==nil)
print('PASS: a lookup in progress does not restore a removed rating')
end

-- Personal and community sources
do
-- Your own rating joins the community score only when both sources
-- (personal and community) are chosen; otherwise each source is used alone.
_G.unpack=table.unpack or unpack
local function stub() return setmetatable({},{__index=function() return function() end end}) end
CreateFrame=function() return stub() end
C_Timer={After=function()end,NewTicker=function()end}
function IsInInstance()return false,'none' end
local a={myName='Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
function a:Now()return self.clock end
function a:Stamp()return 1800000000 end
function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
function a:DisplayName(n)return n end
function a:ValidateStoredTarget(t)return t.faction=='Alliance' and t.guid~=self.myGuid end
function a:NotifyUI()end
function a:RefreshTooltip()end
function a:Log(m) self.logged=m end
function a:Debug()end
RateMeDB=nil
local store=dofile('tests/load_data_addon.lua');store:Bind(a)
dofile('tests/load_communication_addon.lua')(a)
a:InitializeStorage()
a.outbox={};a.counter=0;a.nextSend=0;a.inbound={}
assert(loadfile('RateMe/Highlights.lua'))('RateMe',a)
assert(loadfile('RateMe/Alerts.lua'))('RateMe',a)
function a:StarMarkup() return '*' end

-- You rate the player 1; one other player's verified, fresh rating is 5.
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE',fromGame=true}
assert(a:SaveOwnRating(target,1,{}))
local other={sender='Other-Realm',score=5,rev=1,date=1800000000,freshAt=0}
assert(a:SaveCommunityRating(target,'other-realm',other))
a.runtime.cache[target.guid]={votes={['other-realm']=other}}
a:SyncOwnCachedVote(target.guid)

-- The data function itself.
assert(a:GetFreshCommunityScore(target.guid)==5,'other players only by default')
local both,count=a:GetFreshCommunityScore(target.guid,true)
assert(both==3 and count==2,'own rating included when asked')

-- Stars (nameplate/chat): one score per the chosen sources.
local s=a.db.settings
s.ratingHighlights,s.ratingHighlightsBadge=true,true
s.ratingHighlightsPersonal,s.ratingHighlightsCommunity=false,true
assert(a:IndicatorScore(target.guid)==5,'community only: other players only')
s.ratingHighlightsPersonal,s.ratingHighlightsCommunity=true,false
assert(a:IndicatorScore(target.guid)==1,'personal only: your rating only')
s.ratingHighlightsPersonal,s.ratingHighlightsCommunity=true,true
assert(a:IndicatorScore(target.guid)==3,'both: your rating and everyone else\'s together')
-- Glows follow the same rule for the community part.
s.ratingHighlightsGlow=true
s.ratingHighlightsPersonal,s.ratingHighlightsCommunity=false,true
assert(a:HighlightColor(target.guid)[2]==0.72,'community only: gold from the 5')
s.ratingHighlightsPersonal,s.ratingHighlightsCommunity=true,false
assert(a:HighlightColor(target.guid)[2]==0.19,'personal only: red from your 1')
print('PASS: stars and glows use own rating in the community score only with both sources')

-- Group alerts: community-only does not include your rating.
a:InitializeAlerts()
a.groupMembers={[target.guid]=target};a.groupWarned={}
s.lowRatingAlerts,s.lowRatingThreshold,s.lowRatingPersonalThreshold=true,3,3
s.lowRatingPersonal,s.lowRatingCommunity=false,true
assert(a:WarnForLowRating(target)==false,'community only: the other player\'s 5 is not low')
a.groupWarned={}
s.lowRatingPersonal,s.lowRatingCommunity=true,true
assert(a:WarnForLowRating(target)==true,'both: warns')
assert(a.logged:find('Community: * (2 ratings',1,true),'both: community count includes your rating: '..a.logged)
print('PASS: group alerts use own rating in the community score only with both sources')
end

-- Verified-only averages, unverified counts and sharing
do
-- Peer-supplied (unverified) reviews are listed but never averaged,
-- are shown as a separate count, and are not passed on to other players.
local function boot(name)
 local a={myName=name or 'Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
 function a:Now()return self.clock end
 function a:Stamp()return 1800000000+math.floor(self.clock)end
 function a:CleanName(n)if type(n)~='string' or #n<2 or #n>80 or n:find('[%s|%c]')then return nil end;return n end
 function a:Key(n)local v=self:CleanName(n);return v and v:lower()end
 function a:DisplayName(n)return n end
 function a:ValidateStoredTarget(t)return t.faction=='Alliance' and t.guid~=self.myGuid end
 function a:NotifyUI()end
 function a:RefreshTooltip()end
 function a:Log()end
 function a:Debug()end
 local store=dofile('tests/load_data_addon.lua');store:Bind(a)
 dofile('tests/load_communication_addon.lua')(a)
 a:InitializeStorage()
 a.outbox={};a.counter=0;a.nextSend=0;a.inbound={}
 return a
end
RateMeDB=nil
C_Timer={After=function()end,NewTicker=function()end}
local a=boot()
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}

-- Two verified reviews (5 and 3), one own rating (4) and three made-up peer copies (1 each).
local function verified(author,score)
 local v={sender=author,score=score,rev=1,date=1800000000,freshAt=0}
 assert(a:SaveCommunityRating(target,a:Key(author),v))
 local cache=a.runtime.cache[target.guid] or {votes={}}
 cache.votes[a:Key(author)]=v;a.runtime.cache[target.guid]=cache
end
verified('Alice-Realm',5);verified('Bob-Realm',3)
for _,author in ipairs({'Fakea-Realm','Fakeb-Realm','Fakec-Realm'}) do
 local v={sender=author,score=1,rev=1,date=1800000000}
 assert(a:SaveRelayedCommunityRating(target,a:Key(author),v,'Liar-Realm'))
 a.runtime.cache[target.guid].votes[a:Key(author)]=v
end
assert(a:SaveOwnRating(target,4,{}))
a:SyncOwnCachedVote(target.guid)

-- The average uses verified reviews and your own only.
local summary=a:GetSummary(target.guid)
assert(summary.count==3 and summary.average==4,'average of 5, 3 and own 4: '..tostring(summary.average))
assert(summary.unverifiedCount==3 and summary.peerCount==3,'unverified copies counted separately')
assert(summary.fresh,'freshness is judged on the counted reviews only')
-- Only unverified reviews: no average at all.
local lonely={guid='Player-1-cc',name='Lonely-Realm',faction='Alliance'}
local v={sender='Fakea-Realm',score=1,rev=1,date=1800000000}
assert(a:SaveRelayedCommunityRating(lonely,'fakea-realm',v,'Liar-Realm'))
a.runtime.cache[lonely.guid]={votes={['fakea-realm']=v}}
local only=a:GetSummary(lonely.guid)
assert(only.count==0 and only.average==nil and only.unverifiedCount==1)
-- Recent Lookups shows the verified average and count.
a:RememberTarget(target)
for _,item in ipairs(a:ListRecent()) do
 if item.guid==target.guid then assert(item.score==4 and item.count==3) end
end
print('PASS: averages use verified reviews and your own; unverified counted separately')

-- Only reviews verified here (and your own) are passed on.
local shared=a:CommunityReviewsForSharing(target.guid)
assert(shared['alice-realm'] and shared['bob-realm'] and shared['me-realm'],'verified and own are shared')
assert(not shared['fakea-realm'] and not shared['fakeb-realm'] and not shared['fakec-realm'],'unverified copies are not passed on')
-- End to end: a peer asking us gets 3 replies, none of them unverified.
a:RememberPeer('Friend-Realm')
a:OnMessage('RATEME',a.payload:SharedLookup('ab-1',target,0),'WHISPER','Friend-Realm',false)
local replies={}
for _,job in ipairs(a.outbox) do if job.message:sub(1,2)=='V|' then replies[#replies+1]=job.message end end
assert(#replies==3,'replies: '..#replies)
for _,message in ipairs(replies) do assert(not message:find('Fake',1,true)) end
print('PASS: only verified reviews and your own are passed on')

-- The unverified count is shown separately in windows and tooltips.
_G.unpack=table.unpack or unpack
local function stub() return setmetatable({},{__index=function() return function() end end}) end
CreateFrame=function() return stub() end
UIParent=stub()
assert(loadfile('RateMe/UI.lua'))('RateMe',a)
function a:StarMarkup() return '*' end
function a:RatingNumberText(s) return string.format('%.1f',s) end
local text=a:ScoreText(summary)
assert(text:find('(3 verified ratings)',1,true) and text:find('3 unverified, not counted',1,true),text)
assert(a:ScoreText(only)=='No verified ratings  \194\183  1 unverified, not counted',a:ScoreText(only))
assert(a:ScoreText(nil)=='No ratings available')
local single=a:GetSummary(target.guid);single.unverifiedCount=0
assert(not a:ScoreText(single):find('unverified',1,true),'no unverified note when there are none')
-- Tooltip.
local lines={}
GameTooltip=nil
local tooltip={IsForbidden=function()return false end,GetUnit=function()return 'Target','mouseover' end,
 AddLine=function(_,t)lines[#lines+1]=t end,AddDoubleLine=function(_,l,r)lines[#lines+1]=l..' '..r end}
assert(loadfile('RateMe/Integration.lua'))('RateMe',a)
function a:CaptureUnit() return target end
function a:RequestLookup() return true end
a:AddTooltip(tooltip)
local joined=table.concat(lines,'\n')
assert(joined:find('Community *  (3 verified)',1,true),joined)
assert(joined:find('3 unverified reviews, not counted',1,true),joined)
lines={}
function a:CaptureUnit() return lonely end
a:AddTooltip(tooltip)
joined=table.concat(lines,'\n')
assert(joined:find('No verified community ratings',1,true) and joined:find('1 unverified review, not counted',1,true),joined)
print('PASS: unverified count shown separately in windows and tooltips')
end
