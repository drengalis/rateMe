-- Automatic lookups only run when a feature that needs them is on;
-- lookups the player starts always run.
_G.unpack=table.unpack or unpack
local function stub() return setmetatable({},{__index=function() return function() end end}) end
CreateFrame=function() return stub() end
UIParent=stub()
C_Timer={After=function()end,NewTicker=function()end}
local function boot()
 local a={myName='Me-Realm',myGuid='Player-1-aa',myFaction='Alliance',clock=0}
 function a:Now()return self.clock end
 function a:Stamp()return 1800000000 end
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
local a=boot()
local target={guid='Player-1-bb',name='Target-Realm',faction='Alliance',class='MAGE',fromGame=true}
assert(loadfile('RateMe/Integration.lua'))('RateMe',a)
assert(loadfile('RateMe/Highlights.lua'))('RateMe',a)
assert(loadfile('RateMe/Alerts.lua'))('RateMe',a)
local requests={}
function a:RequestLookup(t,priority) requests[#requests+1]={guid=t.guid,priority=priority};return true end
function a:CaptureUnit() return target end
function a:StarMarkup() return '*' end
local lines={}
local tooltip={IsForbidden=function()return false end,GetUnit=function()return 'Target','mouseover' end,
 AddLine=function(_,t)lines[#lines+1]=t end,AddDoubleLine=function(_,l,r)lines[#lines+1]=l..' '..r end}

-- The hover setting, on by default.
assert(a.db.settings.lookupOnHover==true,'on by default')
a:AddTooltip(tooltip)
assert(#requests==1 and requests[1].guid==target.guid,'hovering looks the player up when on')
requests={};lines={}
a.db.settings.lookupOnHover=false
assert(a:SaveOwnRating(target,4,{}))
a:AddTooltip(tooltip)
assert(#requests==0,'hovering asks no one when off')
assert(table.concat(lines,'\n'):find('Your rating',1,true),'the tooltip still shows what is already known')
print('PASS: hover lookups follow the setting (on by default); tooltip still shows known ratings')

-- Nameplate and group lookups only when their features are on.
local s=a.db.settings
s.ratingHighlights,s.ratingHighlightsGlow,s.ratingHighlightsBadge,s.ratingHighlightsCommunity=false,true,true,true
a:QueuePassiveHighlightLookup(target,2)
assert(#requests==0,'no nameplate lookups with indicators off')
s.ratingHighlights=true
function IsInInstance()return false,'none' end
a:QueuePassiveHighlightLookup(target,2)
assert(#requests==1,'nameplate lookups with community indicators on')
s.ratingHighlightsCommunity=false;requests={}
a:QueuePassiveHighlightLookup(target,2)
assert(#requests==0,'no nameplate lookups when only personal ratings are used')
a:InitializeAlerts()
a.groupMembers={[target.guid]=target};a.groupPending={[target.guid]=target};a.ActiveQueries=function()return 0 end
s.lowRatingAlerts,s.lowRatingCommunity=false,true
a:ProcessGroupLookups()
assert(#requests==0,'no group lookups with alerts off')
s.lowRatingAlerts=true
a:ProcessGroupLookups()
assert(#requests==1,'group lookups with community alerts on')
print('PASS: nameplate and group lookups only when their features are on')

-- Lookups started by opening windows are checked in windows_tests.lua.
