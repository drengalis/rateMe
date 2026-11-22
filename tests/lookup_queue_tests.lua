-- Outgoing lookup budget, the shared lookup queue and inbound flood isolation.
local A = {protocol='1',prefix='RATEME',myName='Me-Realm',myFaction='Alliance',myGuid='Player-123-456',
    CACHE_SECONDS=900,QUERY_SECONDS=15,MAX_PENDING=100,MAX_COMMENT=160}
local t, events = 1000, {}
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
C_ChatInfo={SendAddonMessage=function() return 0 end,SendAddonMessageLogged=function()return 0 end}
function A:Now()return t end
function A:Stamp()return 100000+t end
function A:CleanName(n) if type(n)~='string' or #n < 2 or n:find('[%s|%c]') then return nil end; if not n:find('-',1,true) then return n..'-Realm' end;return n end
function A:Key(n) local s=self:CleanName(n);return s and s:lower() end
function A:ValidateStoredTarget(x) return type(x)=='table' and type(x.guid)=='string' and x.guid:match('^Player%-') ~= nil end
function A:RememberTarget() end
function A:GetOwnRating() return nil end
function A:NotifyUI() end
function A:RefreshTooltip() end
function A:GetSummary() return nil end
function A:Log() end
function A:Debug() end
function A:DebugPacket() end
function A:DisplayName(name) return name end
local S = dofile('tests/load_data_addon.lua')
S:Bind(A)
dofile('tests/load_communication_addon.lua')(A)
-- Binding sets the real limit of 5 running lookups; lift it so these tests
-- exercise the budget on its own (the busy case is tested explicitly).
A.MAX_PENDING=100

local function target(n) return {guid=string.format('Player-T-%03d',n),name=string.format('Target%03d-Realm',n),faction='Alliance'} end
local function reset(start)
 t=start or 1000;events={}
 A.runtime={requests={},cache={},seen={},comments={}}
 A.db={ignored={},authored={[A:Key(A.myName)]={}},settings={},peers={},recent={},community={}};A.data=A.db
 A.outbox={};A.netStats={};A.inbound={};A.nextSend=0;A.counter=0;A.lastHello=0;A.globalInbound=nil
 A.lookupBudget=nil;A.lookupQueue=nil;A.backgroundLookupBudget=nil
 for i=1,10 do local name=string.format('Peer%03d-Realm',i); A.data.peers[A:Key(name)]={name=name,seen=100000} end
end

-- Budget: the very first automatic lookup is never refused, even at time 0.
reset(0)
assert(A:Query(target(1)),'first automatic lookup at login must start')
reset()
assert(A:Query(target(1)))
local ok,reason=A:Query(target(2))
assert(not ok and reason=='budget','automatic lookups are spaced 2 seconds apart')
assert(A.netStats.deferredLookups==1)
assert(A:Query(target(2),false,true),'window lookups are never held back')
advance(t+2);assert(A:Query(target(3)),'allowed again after 2 seconds')
-- 15 lookups per minute in total; window lookups count towards it.
reset()
for i=1,15 do assert(A:Query(target(i),false,true),'interactive '..i) end
advance(t+5)
ok,reason=A:Query(target(16))
assert(not ok and reason=='budget','16th lookup in a minute must wait')
assert(A:Query(target(17),false,true),'window lookups still start over the cap')
advance(1061);assert(A:Query(target(18)),'budget resets after 60 seconds')
print('PASS: lookup budget (first lookup, 2-second spacing, 15/minute, window bypass, reset)')

-- Query reports why it did not start.
reset()
assert(A:Query(target(1)))
ok,reason=A:Query(target(1));assert(not ok and reason=='running')
advance(t+16)
ok,reason=A:Query(target(1));assert(not ok and reason=='fresh')
ok,reason=A:Query({guid='bad'});assert(not ok and reason=='invalid')
A.MAX_PENDING=1;advance(t+2)
assert(A:Query(target(2)))
advance(t+2);ok,reason=A:Query(target(3));assert(not ok and reason=='busy')
A.MAX_PENDING=100
print('PASS: Query reasons (running, fresh, invalid, busy)')

-- Queue: held-back lookups wait and start when the budget allows.
reset()
assert(A:RequestLookup(target(1),1) and A.runtime.requests and next(A.runtime.requests),'starts immediately when allowed')
assert(A:RequestLookup(target(2),2))
assert(A:RequestLookup(target(3),1))
assert(#A.lookupQueue==2 and A.netStats.queuedLookups==2)
assert(A:RequestLookup(target(3),1) and #A.lookupQueue==2,'no duplicate entries')
A:ProcessLookupQueue();assert(#A.lookupQueue==2,'still inside the 2-second spacing')
advance(t+2);A:ProcessLookupQueue()
assert(#A.lookupQueue==1 and A.lookupQueue[1].target.guid==target(2).guid,'priority 1 starts before priority 2')
advance(t+2);A:ProcessLookupQueue();assert(#A.lookupQueue==0)
-- A duplicate request from a higher-priority source promotes the entry.
reset();A:RequestLookup(target(1),1)
A:RequestLookup(target(2),2);A:RequestLookup(target(2),1)
assert(A.lookupQueue[1].priority==1,'entry promoted to priority 1')
-- Entries expire: 35 seconds for nameplates, 60 for everything else.
reset();A:RequestLookup(target(1),1)
A:RequestLookup(target(2),2);A:RequestLookup(target(3),1)
A.lookupBudget.count=15 -- keep the budget full so nothing can start
advance(t+36);A:ProcessLookupQueue()
assert(#A.lookupQueue==1 and A.lookupQueue[1].priority==1,'nameplate entry expired after 35 seconds')
advance(t+25);A:ProcessLookupQueue();assert(#A.lookupQueue==0,'priority-1 entry expired after 60 seconds')
-- A finished/fresh or no-longer-valid entry is dropped instead of retried.
reset();A:RequestLookup(target(1),1);A:RequestLookup(target(1),1)
A.lookupQueue={{target={guid='bad'},priority=1,added=t}}
advance(t+2);A:ProcessLookupQueue();assert(#A.lookupQueue==0)
print('PASS: shared queue (start when allowed, priority order, promotion, expiry, dropping)')

-- Nameplate (priority 2) lookups are capped at 6 per minute.
reset()
for i=1,10 do A:RequestLookup(target(i),2) end
local started=0
for _=1,40 do advance(t+2);local before=A.netStats.queriesStarted or 0;A:ProcessLookupQueue()
 if (A.netStats.queriesStarted or 0)>before then started=started+1 end end
-- Exactly 6 start in the first minute; the other 4 expire (35 s) before the next.
assert(started==6,'background cap: '..started)
print('PASS: nameplate lookups limited to 6 per minute')

-- Full queue: nameplate entries make room for others, never the reverse.
reset();A:RequestLookup(target(1),1)
for i=2,31 do assert(A:RequestLookup(target(i),2)) end
assert(#A.lookupQueue==30)
assert(A:RequestLookup(target(40),1),'priority 1 replaces a nameplate entry')
assert(#A.lookupQueue==30)
local found=false;for _,e in ipairs(A.lookupQueue) do if e.target.guid==target(40).guid then found=true end end
assert(found)
assert(A.lookupQueue[1].target.guid~=target(2).guid,'oldest nameplate entry was dropped')
reset();A:RequestLookup(target(1),1)
for i=2,31 do A:RequestLookup(target(i),1) end
assert(not A:RequestLookup(target(50),2),'a full queue of priority-1 entries refuses nameplates')
print('PASS: full-queue replacement policy')

-- Inbound: a flooding sender is dropped without using the shared allowance.
reset()
local flooder=0
for _=1,200 do if A:AllowInbound('Flooder-Realm') then flooder=flooder+1 end end
assert(flooder==18,'per-sender limit: '..flooder)
assert(A.globalInbound.count==18,'only accepted messages count towards the global allowance')
local others=0
for i=1,100 do if A:AllowInbound(string.format('Client%03d-Realm',i)) then others=others+1 end end
assert(others==100,'other players are still accepted after a flood: '..others)
assert((A.netStats.droppedGlobal or 0)==0 and A.netStats.droppedPeer==182)
print('PASS: per-sender limit checked before the global allowance')
