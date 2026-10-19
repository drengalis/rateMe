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
C_Timer={After=function()end}
local a=boot()
local labels={
 [1]='Leader',[2]='Team Player',[3]='Helpful',[4]='Skilled',[5]='Reliable',[6]='Patient',
 [7]='Fair Looter',[8]='Good Communicator',[9]='Well Prepared',[10]='Knows Mechanics',
 [11]='Protects Teammates',[12]='Good Sportsmanship',[33]='Ninja Looter',[34]='Toxic',
 [35]='Griefer',[36]='Frequently AFK',[37]='Abandons Groups',[38]='Uncooperative',
 [39]='Ignores Mechanics',[40]='Reckless Pulls',[41]='Unprepared',[42]='Poor Communication',
 [43]='Breaks Crowd Control',[44]='Disrespects Loot Rules'}
for id,name in pairs(labels)do
 assert(a.TAG_REGISTRY[id].name==name,'Permanent ID changed: '..id)
 assert(a.TAG_REGISTRY[id].positive==(id<33))
end
assert(a:EncodeReviewTags({1,7,40})=='BHo') -- permanent byte mapping
assert(a:EncodeReviewTags({40,7,1})=='BHo')
assert(a:EncodeReviewTags(nil)=='')
for _,invalid in ipairs({{1,1},{0},{13},{1,2,3,4},{7,33},{9,41},'free text','!!!!'})do
 assert(a:EncodeReviewTags(invalid)==nil)
end
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
assert(a:SaveOwnRating(target,5,{1,7,40}))
local own=a:GetOwnRating(target.guid)
assert(own.tags=='BHo' and own.comment==nil)
assert(not a:SaveOwnRating(target,5,{7,33}))
local base=a.payload:RatingBroadcast(target,own)
local tags=a.payload:ReviewTags('-',target.guid,own.rev,own.tags)
assert(#tags<64 and #own.tags==3)
assert(base:sub(-1)=='0') -- legacy comment flag is always zero
RateMeDB=nil
local b=boot('Other-Realm')
-- Reordered broadcast metadata is buffered, never treated as a standalone vote.
b:OnMessage('RATEME',tags,'CHANNEL','Me-Realm',false)
assert(next(b.db.community)==nil)
b:OnMessage('RATEME',base,'CHANNEL','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].tags=='BHo')
assert(b:IsCommunityReviewVerified(b.db.community[target.guid].votes['me-realm']))
b:OnMessage('RATEME',a.payload:ReviewTags('-',target.guid,1,{2}),'CHANNEL','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].tags=='BHo') -- immutable revision
b:OnMessage('RATEME',tags,'CHANNEL','Mallory-Realm',false)
assert(b.db.community[target.guid].votes['mallory-realm']==nil)
-- Reload keeps only encoded IDs, never labels or written comments.
b=boot('Other-Realm')
assert(b.runtime.cache[target.guid].votes['me-realm'].tags=='BHo')
assert(b.db.community[target.guid].votes['me-realm'].comment==nil)
-- Receivers can disable broadcasts while still getting tags on explicit lookups.
b:SetSetting('receiveRatingBroadcasts',false)
local request='aa-1'
b.runtime.requests[request]={target=target,guid=target.guid,expires=99,votes={},revisions={},responseCount=0}
b:OnMessage('RATEME','R|'..request..'|'..target.guid..'|4|2|1800000000|0','WHISPER','Me-Realm',false)
b:FinishQuery(request)
b:OnMessage('RATEME',a.payload:ReviewTags(request,target.guid,2,{3,4}),'WHISPER','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].tags==a:EncodeReviewTags({3,4}))
assert(b.runtime.cache[target.guid].votes['me-realm'].tags==a:EncodeReviewTags({3,4}))
b:OnMessage('RATEME',a.payload:ReviewTags('-',target.guid,2,{1}),'WHISPER','Me-Realm',false)
assert(b.db.community[target.guid].votes['me-realm'].tags==a:EncodeReviewTags({3,4}))
-- Numeric request/reply still has the protocol-1 shape and no comment payload.
b.outbox={}
b:SaveOwnRating(target,4,{1,4})
b:RememberPeer('Requester-Realm')
b:HandleQuery({'Q','ab-2',target.guid,'Requester-Realm','0'},'Requester-Realm')
assert(#b.outbox==2 and b.outbox[1].message:sub(1,2)=='R|' and b.outbox[1].message:sub(-1)=='0')
assert(b.outbox[2].message:sub(1,2)=='T|')
print('PASS: permanent tag IDs/byte mapping, validation, compact storage, broadcast reordering, authenticated tags, lookup tags and v1 compatibility')
