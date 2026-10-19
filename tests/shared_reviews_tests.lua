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

C_Timer={After=function()end}
local function node(name)
 RateMeDB=nil
 local a=boot(name)
 a.db.settings.sendRatingBroadcasts=false
 return a
end
local root,middle,remote=node('Root-Realm'),node('Middle-Realm'),node('Remote-Realm')
local nodes={['Root-Realm']=root,['Middle-Realm']=middle,['Remote-Realm']=remote}
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE'}
local function save(a,author,score,rev,tags)
 local v={sender=author,score=score,rev=rev,date=1800000000+rev,tags=a:EncodeReviewTags(tags or {})}
 assert(a:SaveCommunityRating(target,a:Key(author),v))
end
assert(middle:SaveOwnRating(target,4,{1,4}))
save(middle,'Alice-Realm',5,1,{1,7})
for i=1,5 do save(remote,'Reviewer'..i..'-Realm',i,1,{1})end
middle:RememberPeer(remote.myName)
local function request(id)
 root.runtime.requests[id]={target=target,guid=target.guid,expires=100,votes={},revisions={},
  responseCount=0,seeded={[root:Key(middle.myName)]=true}}
 middle:OnMessage('RATEME',root.payload:SharedLookup(id,target,2),'WHISPER',root.myName,false)
end
local delivered=0
local function drain()
 for turn=1,100 do
  local work=false
  for _,a in pairs(nodes)do
   local queue=a.outbox;a.outbox={}
   for _,job in ipairs(queue)do
    work=true;delivered=delivered+1
    assert(job.channel=='WHISPER' and #job.message<=255)
    local recipient=assert(nodes[job.target],job.target)
    recipient:OnMessage('RATEME',job.message,job.channel,a.myName,false)
   end
  end
  if not work then return end
 end
 error('unbounded relay loop')
end
request('aa-1');drain()
assert(root:GetSummary(target.guid).count==7)
assert(root:GetSummary(target.guid).peerCount==6)
local votes=root.db.community[target.guid].votes
assert(root:IsCommunityReviewVerified(votes['middle-realm']))
assert(votes['reviewer1-realm'].via=='Middle-Realm' and not root:IsCommunityReviewVerified(votes['reviewer1-realm']))
assert(middle.db.community[target.guid].votes['reviewer1-realm'].via=='Remote-Realm')
assert(votes['reviewer1-realm'].tags==root:EncodeReviewTags({1}))
local score,count=root:GetFreshCommunityScore(target.guid)
assert(score==4 and count==1) -- peer-supplied scores never drive fresh-only indicators
root:FinishQuery('aa-1')
assert(root:GetSummary(target.guid).count==7)
-- Shared tombstones merge through two hops and prevent stale peer resurrection.
save(remote,'Reviewer1-Realm',0,2,{})
request('aa-2');drain()
assert(root.db.community[target.guid].votes['reviewer1-realm'].score==0)
assert(root.runtime.cache[target.guid].votes['reviewer1-realm']==nil)
assert(root:GetSummary(target.guid).count==6)
local stale={sender='Reviewer1-Realm',score=5,rev=1,date=1800000001,tags='B'}
root:OnMessage('RATEME',root.payload:SharedReview('aa-2',target.guid,stale),'WHISPER',middle.myName,false)
assert(root.db.community[target.guid].votes['reviewer1-realm'].score==0)
-- Unsolicited responses, wrong children, expired routes and invalid fields do not persist.
local outsider={sender='Outsider-Realm',score=1,rev=1,date=1800000001,tags='B'}
root:OnMessage('RATEME',root.payload:SharedReview('aa-2',target.guid,outsider),'WHISPER',remote.myName,false)
root:OnMessage('RATEME',root.payload:SharedReview('missing',target.guid,outsider),'WHISPER',middle.myName,false)
assert(not root.db.community[target.guid].votes['outsider-realm'])
-- Directly verified records, including deletions, cannot be replaced by relayed claims.
save(root,'Alice-Realm',5,1,{1,7})
local forged={sender='Alice-Realm',score=1,rev=999,date=1800000999,tags='h'}
root:OnMessage('RATEME',root.payload:SharedReview('aa-2',target.guid,forged),'WHISPER',middle.myName,false)
assert(root.db.community[target.guid].votes['alice-realm'].rev==1)
assert(root:IsCommunityReviewVerified(root.db.community[target.guid].votes['alice-realm']))
-- The actual author can correct even a larger, unverified peer revision.
forged.sender='Reviewer2-Realm'
root:OnMessage('RATEME',root.payload:SharedReview('aa-2',target.guid,forged),'WHISPER',middle.myName,false)
assert(root.db.community[target.guid].votes['reviewer2-realm'].rev==999)
root:HandleRating({'R','aa-2',target.guid,'4','1','1800000001','0'},'Reviewer2-Realm')
assert(root.db.community[target.guid].votes['reviewer2-realm'].rev==1)
root:FinishQuery('aa-2')
assert(root.runtime.cache[target.guid].votes['reviewer2-realm'].score==4)
assert(root:IsCommunityReviewVerified(root.runtime.cache[target.guid].votes['reviewer2-realm']))
-- A forwarded copy of this client's own review must never be endorsed automatically.
assert(not root:SaveRelayedCommunityRating(target,root:Key(root.myName),{sender=root.myName,score=5,rev=99,date=1},middle.myName))
-- Per-lookup forwarded-review cap is independent of the existing direct-review cap.
request('aa-3');middle.outbox={}
for i=1,120 do
 local v={sender='Extra'..i..'-Realm',score=3,rev=1,date=1800000001,tags=''}
 local _,_,args=root:DecodePacket(root.payload:SharedReview('aa-3',target.guid,v),middle.myName)
 root:HandleSharedReview(args,middle.myName)
end
assert(root.runtime.requests['aa-3'].sharedCount==100)
-- Same peer/request repeats do not allocate more routes or resend snapshots.
local before=middle.counter
middle:HandleSharedLookup(select(3,middle:DecodePacket(root.payload:SharedLookup('aa-3',target,2),root.myName)),root.myName)
assert(middle.counter==before)
-- Expired requests/routes cannot accept or retain relay state.
root.clock=101
local _,_,expiredArgs=root:DecodePacket(root.payload:SharedReview('aa-3',target.guid,outsider),middle.myName)
root:HandleSharedReview(expiredArgs,middle.myName)
assert(not root.db.community[target.guid].votes['outsider-realm'])
middle.clock=1000;middle:PruneSharedLookups()
assert(next(middle.sharedRoutes)==nil and next(middle.sharedLookupSeen)==nil)
-- Persistence retains provenance; it never carries direct verification to another user.
RateMeDB=root.db
local restored=boot(root.myName)
assert(restored.db.community[target.guid].votes['reviewer3-realm'].via=='Middle-Realm')
assert(not restored:IsCommunityReviewVerified(restored.db.community[target.guid].votes['reviewer3-realm']))
assert(restored:GetFreshCommunityScore(target.guid)==nil)
print('PASS: multi-peer aggregation, deduplication, tags, tombstones, source verification, author correction, route validation, caps and persistence')
