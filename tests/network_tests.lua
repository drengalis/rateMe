local A = {protocol='1',prefix='RATEME',myName='Me-Realm',myFaction='Alliance',myGuid='Player-123-456',CACHE_SECONDS=900,QUERY_SECONDS=15,MAX_PENDING=5,MAX_COMMENT=160}
local t, events = 0, {}
local function schedule(delay,fn) events[#events+1]={at=t+delay,fn=fn} end
C_Timer={After=schedule,NewTicker=function()end}
local function advance(to)
 while true do
  local index,at=nil, math.huge
  for i,e in ipairs(events) do if e.at <= to and e.at < at then index,at=i,e.at end end
  if not index then break end
  local event=table.remove(events,index);t=at;event.fn()
 end
 t=to
end
IsInGroup=function() return false end
IsInRaid=function() return false end
IsInGuild=function() return false end
local send = {}
C_ChatInfo={SendAddonMessage=function(prefix,msg,ch,target) send[#send+1]={prefix=prefix,msg=msg,ch=ch,target=target};return 0 end,SendAddonMessageLogged=function()return 0 end}
function A:Now()return t end
function A:Stamp()return 100000+t end
function A:CleanName(n) if type(n)~='string' or #n < 2 or n:find('[%s|%c]') then return nil end; if not n:find('-',1,true) then return n..'-Realm' end;return n end
function A:Key(n) local s=self:CleanName(n);return s and s:lower() end
function A:ValidateStoredTarget(x) return type(x)=='table' and x.guid=='Player-ABC-123' end
function A:RememberTarget(x) self.db.recent[x.guid]=self.db.recent[x.guid] or {name=x.name,guid=x.guid} end
function A:GetOwnRating(g) return self.own end
function A:NotifyUI() end
function A:RefreshTooltip() end
function A:GetSummary(g)
 local c=self.runtime.cache[g];if not c then return nil end
 local total,n=0,0
 for _,v in pairs(c.votes or {}) do total=total+v.score;n=n+1 end
 return {average=n>0 and total/n or nil,count=n,comments=0,fresh=true}
end
function A:Log() end
function A:Debug() end
local chunk=assert(loadfile('RateMe/Network.lua'));chunk('RateMe',A)
local target={guid='Player-ABC-123',name='Target-Realm',faction='Alliance'}
local function reset()
 t=0;events={};send={};A.runtime={requests={},cache={},seen={},comments={}};A.db={peers={},recent={},ignored={}};A.own=nil;A.outbox={};A.netStats={};A.inbound={};A.nextSend=0;A.counter=0;A.lastHello=0;A.globalInbound=nil
 for i=1,60 do local name=string.format('Peer%03d-Realm',i); A.db.peers[A:Key(name)]={name=name,seen=100000} end
end
local function countQueued(tag) local n=0;for _,v in ipairs(A.outbox)do if v.message:match('^'..tag..'|') then n=n+1;assert(v.channel=='WHISPER') end end;return n end
local function countActive() local n=0;for _ in pairs(A.runtime.requests)do n=n+1 end;return n end
reset(); assert(A:Query(target));assert(not A:Query(target,true),'same-target force must coalesce');advance(1)
assert(countQueued('Q')==3,'initial wave: '..countQueued('Q'))
advance(5);assert(countQueued('Q')==6,'expansion: '..countQueued('Q'))
advance(10);assert(countQueued('Q')==7,'final wave: '..countQueued('Q'))
assert(A.netStats.querySeeds==7);advance(16);assert(countActive()==0);assert(A.runtime.cache[target.guid].fetchedAt==15.2)
print('PASS: staggered waves, max seven root seeds, whisper-only, completed cache')
reset();assert(A:Query(target));advance(1);local id=next(A.runtime.requests)
for i=1,5 do A:HandleRating({'R',id,target.guid,'5','1','100000','0'},string.format('Voter%03d-Realm',i)) end
advance(10);assert(countQueued('Q')==3,'adequate sample must suppress expansion')
print('PASS: enough replies suppress both expansions')
reset();assert(A:Query(target));advance(1);id=next(A.runtime.requests)
A:HandleRating({'R',id,target.guid,'4','2','100000','0'},'Voter001-Realm')
A:HandleRating({'R',id,target.guid,'5','1','100000','0'},'Voter001-Realm')
assert(A.runtime.requests[id].votes[A:Key('Voter001-Realm')].score==4)
A:HandleRating({'R',id,target.guid,'0','3','100000','0'},'Voter001-Realm')
A:HandleRating({'R',id,target.guid,'5','2','100000','0'},'Voter001-Realm')
assert(A.runtime.requests[id].votes[A:Key('Voter001-Realm')]==nil,'old response revived a deletion')
for i=2,102 do A:HandleRating({'R',id,target.guid,'4','1','100000','0'},string.format('Voter%03d-Realm',i)) end
assert(A.runtime.requests[id].responseCount==100,'response cap')
assert(A.netStats.droppedReplyCap==2)
print('PASS: deduplication, revision tombstone, 100 remote-reviewer cap')
reset();local packet='Q|lookup-1|Player-ABC-123|Requester-Realm|2';A:OnMessage('RATEME',packet,'GUILD','Peer001-Realm',false);assert(#A.outbox==0,'guild query must not dispatch')
A.db.peers[A:Key('Peer001-Realm')]={name='Peer001-Realm',seen=100000}
A:OnMessage('RATEME',packet,'WHISPER','Peer001-Realm',false);assert(countQueued('Q')<=3)
local before=#A.outbox;A:OnMessage('RATEME',packet,'WHISPER','Peer001-Realm',false);assert(#A.outbox==before)
print('PASS: guild query ignored, bounded forwarding, duplicate suppression')
reset();local accepted=0;for i=1,130 do if A:AllowInbound(string.format('Client%03d-Realm',i)) then accepted=accepted+1 end end
assert(accepted==120 and A.netStats.droppedGlobal==10)
advance(21);A:PruneInbound();assert(next(A.inbound)==nil)
print('PASS: global inbound limit and periodic rate-state pruning')
reset();assert(A:Query(target));advance(1);id=next(A.runtime.requests)
assert(A:QueueSend('H|1','GUILD'));assert(A:QueueSend('H|1','PARTY'))
assert(not A:OnMessage('RATEME2','Q|x|Player-ABC-123|Me-Realm|2','WHISPER','Other-Realm',false))
assert(A.netStats.querySeeds==3)
assert(A.outbox[1].channel=='WHISPER')
print('PASS: RATEME prefix and discovery-only broadcasts')
