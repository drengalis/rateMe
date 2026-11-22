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
assert(a:GetFreshCommunityScore(target.guid)==5)

-- Changing the rating replaces the cached copy straight away.
refreshes=0
assert(a:SaveOwnRating(target,1,{}))
assert(a.runtime.cache[target.guid].votes[ownKey].score==1,'cached own vote must follow an edit')
assert(a:GetFreshCommunityScore(target.guid)==1 and refreshes>=1)
print('PASS: editing a rating updates the cached own vote and refreshes highlights')

-- Removing the rating deletes the cached copy straight away.
refreshes=0
assert(a:DeleteOwnRating(target))
assert(a.runtime.cache[target.guid].votes[ownKey]==nil,'cached own vote must be removed')
assert(a:GetFreshCommunityScore(target.guid)==nil and refreshes>=1)
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
assert(a:GetFreshCommunityScore(target.guid)==nil)
print('PASS: a lookup in progress does not restore a removed rating')
